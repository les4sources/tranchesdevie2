# Récupère et enregistre la commission Stripe d'un paiement, en arrière-plan.
#
# Appelé après l'encaissement d'une commande (webhook / page success) pour ne
# pas ralentir la requête, et pour tolérer le délai éventuel de mise à
# disposition de la balance transaction côté Stripe.
class FetchStripeFeeJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(payment)
    StripeFeeService.fetch_for(payment)
  end
end
