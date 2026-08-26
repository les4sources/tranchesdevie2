# Encaisse une commande checkout déjà réservée (statut :pending) en débitant le
# portefeuille du client, puis la passe à :paid. Pendant du OrderPaymentFinalizer
# (paiement Stripe), mais pour le portefeuille interne.
#
# Atomique et à l'abri des courses : le solde est relu et débité SOUS un verrou
# de ligne sur le portefeuille (`with_lock` → SELECT ... FOR UPDATE). Deux
# paiements portefeuille concurrents sont donc sérialisés — le second voit le
# solde déjà décrémenté et échoue proprement au lieu de passer en négatif.
#
# Garde de solde = `available_balance_cents` (et non le solde brut) : on ne
# dépense jamais l'argent réservé aux commandes planifiées du calendrier.
#
# Ne détruit JAMAIS la commande : renvoie true (payé) ou false (`error`
# renseigné) et laisse le contrôleur décider (il détruit la réservation pour
# libérer la capacité, comme le fait le tunnel Stripe).
class WalletCheckoutService
  attr_reader :error

  def self.call(order:)
    new(order).call
  end

  def initialize(order)
    @order = order
    @error = nil
  end

  def call
    wallet = @order.customer.wallet
    if wallet.nil?
      @error = "Aucun portefeuille associé à ce compte"
      return false
    end

    paid = false

    wallet.with_lock do
      if wallet.available_balance_cents < @order.total_cents
        @error = "Solde du portefeuille insuffisant"
        next
      end

      WalletService.debit_for_order(wallet: wallet, order: @order)
      @order.transition_to!(:paid)
      @order.update!(paid_at: Time.current)
      paid = true
    end

    paid
  rescue StandardError => e
    Rails.logger.error("WalletCheckoutService error (order #{@order&.id}): #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    @error ||= "Une erreur est survenue lors du paiement par portefeuille"
    false
  end
end
