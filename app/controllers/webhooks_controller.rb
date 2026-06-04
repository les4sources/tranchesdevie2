class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def stripe
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]
    endpoint_secret = ENV["STRIPE_WEBHOOK_SECRET"]

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, endpoint_secret
      )
    rescue JSON::ParserError => e
      render json: { error: "Invalid JSON" }, status: :bad_request
      return
    rescue Stripe::SignatureVerificationError => e
      render json: { error: "Invalid signature" }, status: :bad_request
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
    when "payment_intent.succeeded"
      result = handle_payment_intent_succeeded(event)
      unless result
        Rails.logger.error("handle_payment_intent_succeeded returned false/nil for event #{event.id}")
      end
    when "payment_intent.payment_failed"
      handle_payment_intent_failed(event)
    when "charge.refunded"
      handle_charge_refunded(event)
    end

    stripe_event.mark_processed!

    render json: { received: true }
  rescue StandardError => e
    Rails.logger.error("Webhook error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    render json: { error: e.message }, status: :internal_server_error
  end

  private

  def handle_payment_intent_succeeded(event)
    payment_intent = event.data.object
    payment_intent_id = payment_intent.id
    metadata = payment_intent.metadata || {}

    Rails.logger.info("Processing payment_intent.succeeded webhook for: #{payment_intent_id}")

    # Check if this is a wallet reload
    if metadata["type"] == "wallet_reload"
      return handle_wallet_reload(payment_intent)
    end

    # La commande est créée (réservée) au moment du paiement (create_payment_intent),
    # donc elle existe déjà ici. Le webhook ne fait que l'encaisser — il ne crée
    # jamais de commande (sinon on contournerait le contrôle de capacité).
    order = Order.uncached { Order.find_by(payment_intent_id: payment_intent_id) }

    unless order
      Rails.logger.error("Webhook: aucune commande pour le PaymentIntent #{payment_intent_id} (réservation manquante)")
      Sentry.capture_message("Stripe webhook: commande introuvable pour #{payment_intent_id}") if defined?(Sentry)
      return false
    end

    OrderPaymentFinalizer.call(order: order, payment_intent_id: payment_intent_id)
    Rails.logger.info("Order #{order.id} encaissée via webhook (PI #{payment_intent_id})")
    true
  rescue StandardError => e
    Rails.logger.error("Exception in handle_payment_intent_succeeded for payment_intent #{payment_intent_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    Sentry.capture_exception(e) if defined?(Sentry)
    false
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

  def handle_wallet_reload(payment_intent)
    payment_intent_id = payment_intent.id
    metadata = payment_intent.metadata || {}
    customer_id = metadata["customer_id"]

    Rails.logger.info("Processing wallet reload for customer #{customer_id}, amount: #{payment_intent.amount}")

    customer = Customer.find_by(id: customer_id)
    unless customer
      Rails.logger.error("Customer not found for wallet reload: #{customer_id}")
      return false
    end

    wallet = customer.wallet || customer.create_wallet!

    # Idempotency check
    if wallet.wallet_transactions.exists?(stripe_payment_intent_id: payment_intent_id)
      Rails.logger.info("Wallet reload already processed: #{payment_intent_id}")
      return true
    end

    WalletService.top_up(
      wallet: wallet,
      amount_cents: payment_intent.amount,
      stripe_payment_intent_id: payment_intent_id
    )

    Rails.logger.info("Wallet reload successful: #{payment_intent.amount} cents for customer #{customer_id}")
    true
  rescue StandardError => e
    Rails.logger.error("Error processing wallet reload: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end
end
