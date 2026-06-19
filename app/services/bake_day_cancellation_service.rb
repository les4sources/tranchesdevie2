# Annule une fournée entière et rembourse tous les clients qui avaient payé.
#
# Contrairement au remboursement à l'unité (RefundService), ce service :
#   - ignore le cut-off (une fournée annulée l'est forcément après la clôture) ;
#   - gère les deux modes d'encaissement : Stripe (remboursement sur la carte)
#     et portefeuille (recrédit du solde) ;
#   - bascule chaque commande concernée en `cancelled` et prévient le client.
#
# Les commandes payées hors-ligne (espèces) sont annulées mais signalées dans
# `manual_refund_orders` : le remboursement se fait alors à la main.
class BakeDayCancellationService
  # Statuts pour lesquels une annulation a un sens (et dont la transition vers
  # `cancelled` est autorisée par la machine à états de Order).
  PROCESSABLE_STATUSES = %w[paid ready unpaid planned].freeze

  Result = Struct.new(
    :stripe_refunds_count,
    :wallet_refunds_count,
    :refunded_cents,
    :manual_refund_orders,
    :cancelled_without_refund_count,
    :failures,
    keyword_init: true
  ) do
    def refunded_count
      stripe_refunds_count + wallet_refunds_count
    end

    def total_cancelled_count
      refunded_count + manual_refund_orders.size + cancelled_without_refund_count
    end

    def success?
      failures.empty?
    end
  end

  attr_reader :bake_day

  def initialize(bake_day)
    @bake_day = bake_day
  end

  def call
    @stripe_refunds_count = 0
    @wallet_refunds_count = 0
    @refunded_cents = 0
    @manual_refund_orders = []
    @cancelled_without_refund_count = 0
    @failures = []

    orders.find_each { |order| process(order) }

    Result.new(
      stripe_refunds_count: @stripe_refunds_count,
      wallet_refunds_count: @wallet_refunds_count,
      refunded_cents: @refunded_cents,
      manual_refund_orders: @manual_refund_orders,
      cancelled_without_refund_count: @cancelled_without_refund_count,
      failures: @failures
    )
  end

  private

  def orders
    bake_day.orders.where(status: PROCESSABLE_STATUSES)
  end

  def process(order)
    refunded = cancel_and_refund(order)
    notify(order, refunded: refunded)
  rescue StandardError => e
    @failures << { order: order.order_number, error: e.message }
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  # Annule la commande en remboursant selon le mode d'encaissement.
  # Renvoie true si de l'argent a effectivement été rendu au client (Stripe ou
  # portefeuille), false sinon (commande non encaissée, ou à rembourser à la main).
  def cancel_and_refund(order)
    case order.payment_method
    when :stripe
      refund_stripe(order)
      order_transaction(order) { order.payment.update!(status: :refunded) }
      @stripe_refunds_count += 1
      @refunded_cents += order.total_cents
      true
    when :wallet
      order_transaction(order) { WalletService.refund_for_order(wallet: order.customer.wallet, order: order) }
      @wallet_refunds_count += 1
      @refunded_cents += order.total_cents
      true
    else
      # On lit l'état d'encaissement AVANT la transition (qui change le statut).
      was_paid = order.payment_received?
      order.transition_to!(:cancelled)
      if was_paid
        # Payée mais sans trace d'encaissement en ligne (paiement hors-ligne) :
        # remboursement manuel à effectuer.
        @manual_refund_orders << order.order_number
      else
        @cancelled_without_refund_count += 1
      end
      false
    end
  end

  # Remboursement Stripe hors transaction DB : on ne veut pas qu'un échec de
  # mise à jour locale survienne après un remboursement déjà passé chez Stripe.
  def refund_stripe(order)
    refund = Stripe::Refund.create(payment_intent: order.payment.stripe_payment_intent_id)
    return if refund.status == "succeeded"

    raise "Remboursement Stripe non abouti (statut: #{refund.status})"
  end

  def order_transaction(order)
    ActiveRecord::Base.transaction do
      yield
      order.transition_to!(:cancelled)
    end
  end

  def notify(order, refunded:)
    return unless order.customer.sms_enabled?

    SmsService.send_bake_cancelled(order, refunded: refunded)
  rescue StandardError => e
    # Un échec d'envoi de SMS ne doit pas faire échouer l'annulation déjà actée.
    Rails.logger.error("send_bake_cancelled a échoué pour #{order.order_number}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
