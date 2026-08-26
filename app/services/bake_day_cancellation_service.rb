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

  # Aperçu (dry-run) de ce qu'une annulation ferait, SANS rien écrire en base.
  # Alimente l'écran de confirmation chiffré : il partage exactement la même
  # source (`PROCESSABLE_STATUSES` + `Order#payment_method`) que `#call`, donc
  # aucun écart n'est possible entre l'aperçu et l'exécution réelle.
  Preview = Struct.new(
    :orders_count,
    :stripe_count,
    :stripe_cents,
    :wallet_count,
    :wallet_cents,
    :manual_refund_count,
    :unpaid_count,
    :refund_cents,
    :sms_count,
    keyword_init: true
  ) do
    def any_orders?
      orders_count.positive?
    end

    # Total « non encaissé en ligne » : commandes sans trace Stripe/portefeuille
    # (payées hors-ligne à rembourser à la main + jamais encaissées).
    def non_online_count
      manual_refund_count + unpaid_count
    end

    def refund_euros
      refund_cents / 100.0
    end

    def stripe_euros
      stripe_cents / 100.0
    end

    def wallet_euros
      wallet_cents / 100.0
    end
  end

  attr_reader :bake_day

  def initialize(bake_day)
    @bake_day = bake_day
  end

  def preview
    stripe_count = wallet_count = 0
    stripe_cents = wallet_cents = 0
    manual_refund_count = unpaid_count = sms_count = 0

    preview_orders.each do |order|
      sms_count += 1 if order.customer.sms_enabled?

      case order.payment_method
      when :stripe
        stripe_count += 1
        stripe_cents += order.total_cents
      when :wallet
        wallet_count += 1
        wallet_cents += order.total_cents
      else
        if order.payment_received?
          manual_refund_count += 1
        else
          unpaid_count += 1
        end
      end
    end

    Preview.new(
      orders_count: stripe_count + wallet_count + manual_refund_count + unpaid_count,
      stripe_count: stripe_count,
      stripe_cents: stripe_cents,
      wallet_count: wallet_count,
      wallet_cents: wallet_cents,
      manual_refund_count: manual_refund_count,
      unpaid_count: unpaid_count,
      refund_cents: stripe_cents + wallet_cents,
      sms_count: sms_count
    )
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

  # Même périmètre que `orders`, mais avec les associations nécessaires au
  # calcul du dry-run préchargées (évite les N+1 sur `payment_method`,
  # `payment_received?` et `customer.sms_enabled?`).
  def preview_orders
    orders.includes(:payment, :wallet_transactions, :customer)
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
    # `pending` est un succès : les remboursements Bancontact/SEPA sont asynchrones
    # (cf. RefundService::SUCCESSFUL_STRIPE_REFUND_STATUSES).
    return if RefundService::SUCCESSFUL_STRIPE_REFUND_STATUSES.include?(refund.status)

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
