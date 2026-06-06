# Récupère la commission Stripe (frais) d'un paiement et la stocke sur le
# Payment (`stripe_fee_cents`).
#
# La commission n'est pas portée par le PaymentIntent : il faut passer par la
# Charge associée, puis par sa BalanceTransaction qui expose le champ `fee`.
#
# Idempotent : si la commission est déjà enregistrée, on ne refait pas d'appel
# API. Sûr d'être appelé plusieurs fois (webhook, job de backfill).
class StripeFeeService
  def self.fetch_for(payment)
    new(payment).fetch
  end

  def initialize(payment)
    @payment = payment
  end

  # Renvoie la commission en cents (Integer) si elle a pu être récupérée, sinon nil.
  def fetch
    return @payment.stripe_fee_cents if @payment.stripe_fee_recorded?
    return nil if @payment.stripe_payment_intent_id.blank?

    charge = latest_charge
    return nil if charge.nil? || charge.balance_transaction.blank?

    balance_transaction = Stripe::BalanceTransaction.retrieve(charge.balance_transaction)
    fee_cents = balance_transaction.fee
    @payment.update!(stripe_fee_cents: fee_cents)
    fee_cents
  rescue Stripe::StripeError => e
    Rails.logger.error("StripeFeeService: erreur Stripe pour paiement #{@payment.id} (PI #{@payment.stripe_payment_intent_id}): #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end

  private

  def latest_charge
    Stripe::Charge.list(payment_intent: @payment.stripe_payment_intent_id, limit: 1).data.first
  end
end
