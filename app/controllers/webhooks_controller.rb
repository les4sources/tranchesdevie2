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
      handle_payment_intent_succeeded(event)
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

    # Find or create order (idempotency check)
    order = Order.find_by(payment_intent_id: payment_intent_id)

    unless order
      # Find customer from metadata
      customer_id = payment_intent.metadata&.customer_id
      bake_day_id = payment_intent.metadata&.bake_day_id

      return unless customer_id && bake_day_id

      customer = Customer.find(customer_id)
      bake_day = BakeDay.find(bake_day_id)

      # Reconstruct cart from session or metadata
      # For now, we'll need to store cart in order creation or retrieve from session
      # This is a simplified version - in production, store cart items in metadata or session
      cart_items = JSON.parse(payment_intent.metadata[:cart_items] || '[]') rescue []

      service = OrderCreationService.new(
        customer: customer,
        bake_day: bake_day,
        cart_items: cart_items,
        payment_intent_id: payment_intent_id
      )

      order = service.call
    end

    if order
      order.transition_to!(:paid)
      
      # Create payment record
      Payment.find_or_create_by!(order: order) do |payment|
        payment.stripe_payment_intent_id = payment_intent_id
        payment.status = :succeeded
      end

      # Send confirmation SMS
      SmsService.send_confirmation(order)
    end
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

