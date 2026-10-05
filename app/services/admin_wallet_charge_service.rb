# Encaisse depuis l'admin une commande due en débitant le portefeuille du
# client : le boulanger a saisi la commande à la main pour une cliente dont le
# portefeuille est chargé, et préfère y prélever plutôt que de laisser la
# commande « Non payée ».
#
# Mêmes commandes que le pointage hors-ligne (OfflinePaymentService.settleable?) :
# une vente due, pas encore payée, sans trace Stripe ni portefeuille. Le débit
# laisse une trace `order_debit`, donc la commande devient un paiement TRACÉ
# (Order#payment_method → :wallet) et ne se pointe plus à la main ensuite.
#
# Garde de solde = `available_balance_cents`, sous verrou de ligne, comme
# WalletCheckoutService : on ne dépense jamais l'argent réservé aux commandes
# planifiées du calendrier, et deux prélèvements concurrents sont sérialisés.
class AdminWalletChargeService
  attr_reader :error

  def self.chargeable?(order)
    order.customer&.wallet.present? && OfflinePaymentService.settleable?(order)
  end

  def self.call(order:)
    new(order).call
  end

  def initialize(order)
    @order = order
    @error = nil
  end

  def call
    return false unless charge

    # Hors du bloc ci-dessus : un souci d'e-mail ne doit pas faire croire que
    # le prélèvement, déjà committé, a échoué.
    OrderNotificationService.send_party_accounting_notification(@order)
    true
  end

  private

  def charge
    unless OfflinePaymentService.settleable?(@order)
      @error = "Cette commande n'est pas à encaisser"
      return false
    end

    wallet = @order.customer&.wallet
    if wallet.nil?
      @error = "Ce client n'a pas de portefeuille"
      return false
    end

    paid = false

    wallet.with_lock do
      if wallet.available_balance_cents < @order.total_cents
        @error = "Solde du portefeuille insuffisant"
        next
      end

      WalletService.debit_for_order(wallet: wallet, order: @order)

      attributes = { payment_status: :paid, offline_payment_method: nil }
      attributes[:paid_at] = Time.current if @order.read_attribute(:paid_at).blank?
      # Une commande saisie en admin naît `unpaid` : elle passe à `paid`. Une
      # commande déjà prête ou remise garde son statut logistique (#275).
      attributes[:status] = :paid if @order.unpaid?
      @order.update!(attributes)
      paid = true
    end

    paid
  rescue StandardError => e
    Rails.logger.error("AdminWalletChargeService error (order #{@order&.id}): #{e.class} - #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    @error ||= "Une erreur est survenue lors du prélèvement sur le portefeuille"
    false
  end
end
