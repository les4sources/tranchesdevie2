# Encaisse une commande déjà créée (réservée) après confirmation du paiement
# Stripe. Idempotent : sûr d'être appelé plusieurs fois (webhook, page success,
# job de nettoyage) pour le même PaymentIntent.
class OrderPaymentFinalizer
  def self.call(order:, payment_intent_id:)
    new(order, payment_intent_id).call
  end

  def initialize(order, payment_intent_id)
    @order = order
    @payment_intent_id = payment_intent_id
  end

  def call
    @order.transition_to!(:paid) if @order.can_transition_to?(:paid)
    @order.update!(paid_at: Time.current) if @order.read_attribute(:paid_at).blank?

    payment = Payment.find_or_create_by!(order: @order) do |p|
      p.stripe_payment_intent_id = @payment_intent_id
      p.status = :succeeded
    end

    # N'envoyer la confirmation et ne récupérer la commission Stripe qu'au
    # premier enregistrement du paiement (idempotent face à la course webhook /
    # page success / job).
    if payment.previously_new_record?
      OrderNotificationService.send_confirmation(@order)
      FetchStripeFeeJob.perform_later(payment)
    end

    @order
  end
end
