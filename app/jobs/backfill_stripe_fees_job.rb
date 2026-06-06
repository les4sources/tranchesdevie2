# Récupère rétroactivement la commission Stripe des paiements existants qui
# n'ont pas encore de `stripe_fee_cents`.
#
# Job one-shot, à lancer manuellement après le déploiement :
#   BackfillStripeFeesJob.perform_later
class BackfillStripeFeesJob < ApplicationJob
  queue_as :default

  def perform
    Payment.succeeded.where(stripe_fee_cents: nil).find_each do |payment|
      StripeFeeService.fetch_for(payment)
    end
  end
end
