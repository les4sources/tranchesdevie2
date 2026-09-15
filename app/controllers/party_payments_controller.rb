# Règlement d'une réservation de Pizza party validée (#pizza-parties).
#
# La page vit HORS SESSION : elle ne connaît que le jeton public de la commande,
# reçu par e-mail. C'est ce qui permet au client de payer depuis n'importe quel
# appareil, des jours après sa demande, sans se reconnecter — et c'est pourquoi
# elle ne passe ni par le panier ni par le checkout.
class PartyPaymentsController < ApplicationController
  before_action :load_order
  before_action :ensure_payable, only: [ :show, :create_payment_intent ]

  def show
    @party_request = @order.party_request
    @persons = current_persons
    @variant_price_cents = paton_unit_price_cents
    @forfait_cents = forfait_cents
    @stripe_public_key = ENV["STRIPE_PUBLIC_KEY"]
  end

  # Confirme le nombre de participants ET renvoie le client_secret d'un
  # PaymentIntent au bon montant. Les deux gestes sont indissociables : un PI
  # créé avant la confirmation encaisserait le mauvais total.
  def create_payment_intent
    service = PartyPaymentService.new(@order)

    unless service.confirm_headcount!(params[:persons])
      render json: { success: false, error: service.errors.to_sentence }, status: :unprocessable_entity
      return
    end

    client_secret = service.payment_intent_client_secret

    if client_secret.nil?
      render json: { success: false, error: service.errors.to_sentence }, status: :unprocessable_entity
      return
    end

    render json: {
      success: true,
      client_secret: client_secret,
      total_cents: @order.reload.total_cents,
      total_label: helpers.number_to_currency(@order.total_euros, unit: "€", separator: ",", delimiter: "")
    }
  end

  # Retour de Stripe. L'encaissement passe par OrderPaymentFinalizer, comme tous
  # les autres chemins de paiement — le webhook fera le même travail de son côté,
  # le service est idempotent.
  def success
    payment_intent_id = params[:payment_intent].presence || @order.payment_intent_id

    if payment_intent_id.present? && @order.awaiting_payment?
      finalize(payment_intent_id)
    end

    @order.reload
    @party_request = @order.party_request
  end

  private

  def load_order
    @order = Order.find_by!(public_token: params[:token])
  end

  def ensure_payable
    return if @order.awaiting_payment?

    redirect_to party_payment_success_path(token: @order.public_token)
  end

  def finalize(payment_intent_id)
    intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
    return unless intent.status == "succeeded"

    # Garde-fou : le montant encaissé doit être celui de la commande. Un écart
    # signifie que le nombre de participants a bougé entre la création du
    # PaymentIntent et le paiement (deux onglets, retour arrière). On encaisse
    # quand même — l'argent est pris, refuser laisserait le client payé sans
    # réservation — mais on le signale pour régularisation.
    if intent.amount != @order.total_cents
      message = "PartyPayment: montant encaissé #{intent.amount} ≠ commande #{@order.total_cents} (commande #{@order.id})"
      Rails.logger.error(message)
      Sentry.capture_message(message, level: :error) if defined?(Sentry)
    end

    OrderPaymentFinalizer.call(order: @order, payment_intent_id: payment_intent_id)
  rescue Stripe::StripeError => e
    Rails.logger.error("PartyPayment: retour Stripe illisible pour commande #{@order.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def current_persons
    @order.order_items.includes(product_variant: :product)
          .select { |item| item.product_variant.product.pizza_party_role_party? }
          .sum(&:qty)
  end

  def paton_unit_price_cents
    item = @order.party_request&.party_request_items&.includes(product_variant: :product)
                 &.find { |i| i.product_variant.product.pizza_party_role_party? }
    item&.net_unit_price_cents || 0
  end

  def forfait_cents
    items = @order.party_request&.party_request_items&.includes(product_variant: :product) || []
    items.reject { |i| i.product_variant.product.pizza_party_role_party? }.sum(&:total_cents)
  end
end
