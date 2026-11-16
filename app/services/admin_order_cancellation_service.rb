# Annulation d'une commande de pain depuis sa fiche admin, AVEC le sort de
# l'argent décidé dans le même geste (#annulation-portefeuille).
#
# Le cas réel : Stéphanie annule un froment 1 kg pour mardi depuis « Modifier »,
# puis ne trouve nulle part comment recréditer le portefeuille de la cliente —
# le statut « Annulée » ne rend rien, et le bouton « Rembourser » disparaît dès
# que la commande n'est plus « payée » (ou que le cut-off est passé). Ici, le
# boulanger choisit au moment d'annuler : portefeuille, carte (Stripe) ou rien.
#
# Appelé sur une commande DÉJÀ annulée, le service ne fait que rembourser : c'est
# la porte de rattrapage des annulations faites sans remboursement.
#
# Différences voulues avec RefundService (qui reste le remboursement intégral
# des parties et du parcours historique) :
#   - pas de garde de cut-off : après le cut-off, c'est justement l'admin qui
#     décide d'un geste ;
#   - le montant est ce qui reste réellement encaissé (total moins les
#     remboursements partiels déjà faits) ;
#   - on peut rendre sur le portefeuille une commande payée par carte : c'est
#     souvent ce que la cliente préfère, et ça évite un aller-retour Stripe.
class AdminOrderCancellationService
  REFUND_CHANNELS = %w[wallet stripe none].freeze

  attr_reader :order, :error, :refunded_cents, :refund_channel

  def initialize(order, refund: "wallet", notify: true)
    @order = order
    @refund_channel = refund.to_s
    @notify = ActiveModel::Type::Boolean.new.cast(notify)
    @refunded_cents = 0
  end

  def call
    return fail!("Cette commande ne peut pas être annulée ici.") unless cancellable_or_cancelled?
    return fail!("Mode de remboursement inconnu.") unless REFUND_CHANNELS.include?(@refund_channel)

    amount_cents = order.refundable_remaining_cents
    channel = amount_cents.positive? ? @refund_channel : "none"
    if channel == "stripe" && !stripe_refundable?
      return fail!("Cette commande n'a pas été payée par carte : rembourse-la sur le portefeuille.")
    end
    if order.cancelled? && channel == "none"
      return fail!("Rien à rembourser sur cette commande.")
    end

    # Stripe d'abord, HORS transaction de base : si Stripe refuse, rien n'a bougé.
    refund_on_stripe!(amount_cents) if channel == "stripe"

    ActiveRecord::Base.transaction do
      order.update!(status: :cancelled) unless order.cancelled?
      credit_wallet!(amount_cents) if channel == "wallet"
    end
    # Les transactions déjà chargées (calcul du montant) sont périmées : sans ce
    # reset, la synchro lirait « payé » au lieu de « remboursé ».
    order.wallet_transactions.reset
    order.sync_payment_status!

    @refunded_cents = channel == "none" ? 0 : amount_cents
    @refund_channel = channel
    notify_customer if @notify && @refunded_cents.positive?
    true
  rescue Stripe::StripeError => e
    Sentry.capture_exception(e) if defined?(Sentry)
    fail!("Erreur Stripe : #{e.message}")
  rescue ActiveRecord::RecordInvalid => e
    fail!(e.record.errors.full_messages.to_sentence)
  end

  def self.stripe_refundable?(order)
    order.payment.present? && order.payment.succeeded?
  end

  private

  def cancellable_or_cancelled?
    order.admin_cancellable? || (order.cancelled? && !order.party?)
  end

  def stripe_refundable?
    self.class.stripe_refundable?(order)
  end

  def refund_on_stripe!(amount_cents)
    refund = Stripe::Refund.create({
      payment_intent: order.payment.stripe_payment_intent_id,
      amount: amount_cents
    })

    unless RefundService::SUCCESSFUL_STRIPE_REFUND_STATUSES.include?(refund.status)
      raise Stripe::StripeError, "remboursement refusé (#{refund.failure_reason || refund.status})"
    end

    # Le reste encaissé est rendu en entier : la commande est remboursée.
    order.payment.update!(status: :refunded)
  end

  def credit_wallet!(amount_cents)
    wallet = order.customer.wallet || order.customer.create_wallet!
    wallet.with_lock do
      WalletService.refund_for_order(wallet: wallet, order: order, amount_cents: amount_cents)
    end
  end

  def notify_customer
    SmsService.send_admin_cancellation_refund(order, amount_cents: @refunded_cents, channel: @refund_channel)
  rescue StandardError => e
    # L'argent est rendu : un SMS qui échoue ne doit pas faire croire l'inverse.
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def fail!(message)
    @error = message
    false
  end
end
