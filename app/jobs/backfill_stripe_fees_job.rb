# Récupère rétroactivement la commission Stripe des paiements existants qui
# n'ont pas encore de `stripe_fee_cents`.
#
# Borné et idempotent : ne traite que `Payment.succeeded` dont la commission
# n'est pas encore connue (`stripe_fee_cents` NULL). Utile car la
# BalanceTransaction Stripe n'est pas toujours disponible au moment du finalize
# (Bancontact asynchrone notamment).
#
# Planifié toutes les 3 h en production (config/recurring.yml → backfill_stripe_fees)
# pour rattraper progressivement les trous. Pour un rattrapage immédiat après un
# déploiement, le lancer aussi manuellement :
#   BackfillStripeFeesJob.perform_later
class BackfillStripeFeesJob < ApplicationJob
  queue_as :default

  def perform
    Payment.succeeded.where(stripe_fee_cents: nil).find_each do |payment|
      StripeFeeService.fetch_for(payment)
    end
  end
end
