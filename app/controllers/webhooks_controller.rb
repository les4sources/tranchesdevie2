class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, endpoint_secret
      )
    rescue JSON::ParserError => e
      render json: { error: 'Invalid JSON' }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      render json: { error: 'Invalid signature' }, status: :bad_request
      return
    end

    # Check idempotency
    if StripeEvent.exists?(event_id: event.id)
      render json: { received: true }
      return
    end

    # Store event
    stripe_event = StripeEvent.create!(
      event_id: event.id,
      event_type: event.type,
      payload: event.data.object.to_json
    )

    # Process event
    case event.type
    when 'payment_intent.succeeded'
      result = handle_payment_intent_succeeded(event)
      unless result
        Rails.logger.error("handle_payment_intent_succeeded returned false/nil for event #{event.id}")
      end
    when 'payment_intent.payment_failed'
      handle_payment_intent_failed(event)
    when 'charge.refunded'
      handle_charge_refunded(event)
    end

    stripe_event.mark_processed!

    render json: { received: true }
  rescue StandardError => e
    Rails.logger.error("Webhook error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    render json: { error: e.message }, status: :internal_server_error
  end

  def telerivet
    body_text = params[:content] || params[:body] || request.body.read

    # Parse for STOP keyword
    if body_text.to_s.upcase.strip == 'STOP'
      phone_e164 = params[:from_number] || params[:from]
      
      if phone_e164.present?
        customer = Customer.find_by(phone_e164: phone_e164)
        if customer
          customer.opt_out_sms!
        end
      end
    end

    # Store inbound message
    SmsMessage.create_inbound(
      params[:from_number] || params[:from] || 'unknown',
      params[:to_number] || params[:to] || ENV['TELERIVET_PHONE_NUMBER'] || 'unknown',
      body_text
    )

    render json: { received: true }
  rescue StandardError => e
    Rails.logger.error("Telerivet webhook error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def handle_payment_intent_succeeded(event)
    payment_intent = event.data.object
    payment_intent_id = payment_intent.id

    Rails.logger.info("Processing payment_intent.succeeded webhook for: #{payment_intent_id}")

    # Find or create order (idempotency check)
    order = Order.uncached { Order.find_by(payment_intent_id: payment_intent_id) }

    unless order
      Rails.logger.info("Order not found for payment_intent #{payment_intent_id}, attempting to create...")
      
      # Find customer from metadata (phone_e164 or customer_id)
      # Metadata is a hash, access with bracket notation
      metadata = payment_intent.metadata || {}
      phone_e164 = metadata[:phone_e164] || metadata['phone_e164']
      customer_id = metadata[:customer_id] || metadata['customer_id']
      bake_day_id = metadata[:bake_day_id] || metadata['bake_day_id']

      Rails.logger.info("Payment intent metadata - phone_e164: #{phone_e164}, customer_id: #{customer_id}, bake_day_id: #{bake_day_id}")

      unless bake_day_id
        Rails.logger.error("No bake_day_id in payment intent #{payment_intent_id} metadata")
        return
      end

      # Find or create customer
      if customer_id.present?
        customer = Customer.find_by(id: customer_id)
        Rails.logger.info("Found customer by id: #{customer_id}" + (customer ? " (#{customer.id})" : " (not found)"))
      elsif phone_e164.present?
        customer = Customer.find_or_create_by(phone_e164: phone_e164)
        Rails.logger.info("Found or created customer by phone_e164: #{phone_e164} (id: #{customer.id})")
      else
        Rails.logger.error("No customer_id or phone_e164 in payment intent #{payment_intent_id} metadata")
        return
      end

      unless customer
        Rails.logger.error("Failed to find or create customer for payment_intent #{payment_intent_id}")
        return
      end

      bake_day = BakeDay.find_by(id: bake_day_id)
      unless bake_day
        Rails.logger.error("Bake day not found with id: #{bake_day_id} for payment_intent #{payment_intent_id}")
        return
      end

      # Reconstruct cart from metadata
      cart_items_json = metadata[:cart_items] || metadata['cart_items'] || '[]'
      cart_items = JSON.parse(cart_items_json) rescue []
      Rails.logger.info("Parsed cart_items from metadata: #{cart_items.size} items")

      unless cart_items.any?
        Rails.logger.error("No cart items found in payment intent #{payment_intent_id} metadata")
        return
      end

      service = OrderCreationService.new(
        customer: customer,
        bake_day: bake_day,
        cart_items: cart_items,
        payment_intent_id: payment_intent_id
      )

      order = service.call

      unless order
        Rails.logger.error("OrderCreationService failed for payment_intent #{payment_intent_id}. Errors: #{service.errors.join(', ')}")
        return
      end

      Rails.logger.info("Order created successfully via webhook: #{order.id} for payment_intent #{payment_intent_id}")
    else
      Rails.logger.info("Order already exists for payment_intent #{payment_intent_id}: #{order.id}")
    end

    if order
      order.transition_to!(:paid)
      
      # Create payment record
      Payment.find_or_create_by!(order: order) do |payment|
        payment.stripe_payment_intent_id = payment_intent_id
        payment.status = :succeeded
      end
      
      Rails.logger.info("Order #{order.id} marked as paid and payment record created")
      return true
    else
      Rails.logger.error("Order is nil after processing payment_intent #{payment_intent_id}")
      return false
    end
  rescue StandardError => e
    Rails.logger.error("Exception in handle_payment_intent_succeeded for payment_intent #{payment_intent_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    Sentry.capture_exception(e) if defined?(Sentry)
    return false
  end

  def handle_payment_intent_failed(event)
    payment_intent = event.data.object
    order = Order.find_by(payment_intent_id: payment_intent.id)

    if order
      # Update payment status
      payment = order.payment
      if payment
        payment.update!(status: :failed)
      end

      # Optionally notify customer
      Rails.logger.info("Payment failed for order #{order.order_number}")
    end
  end

  def handle_charge_refunded(event)
    charge = event.data.object
    payment_intent_id = charge.payment_intent

    order = Order.find_by(payment_intent_id: payment_intent_id)
    return unless order

    order.payment&.update!(status: :refunded)
    order.transition_to!(:cancelled) unless order.cancelled?
  end
end

