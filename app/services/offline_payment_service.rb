# Pointage d'un encaissement HORS LIGNE (liquide, virement) — la seule trace
# que l'app aura jamais d'un tel paiement (#275).
#
# Point unique d'écriture, partagé par la remise au jour de cuisson, la fiche
# de commande et la sélection groupée de la fiche client : poser le moyen, le
# statut financier, la date, et prévenir la compta pour une party privée.
class OfflinePaymentService
  METHODS = %w[cash transfer].freeze

  # Commandes qu'on peut pointer : une vente due (CA facturé) pas encore payée.
  # Ni une commande en cours de paiement Stripe (`pending`), ni une planifiée
  # que le portefeuille débitera, ni une annulée, ni une déjà marquée payée.
  def self.settleable?(order)
    Order::COMPLETED_STATUSES.include?(order.status) &&
      order.payment_status_unpaid? && !order.tracked_payment?
  end

  def self.mark!(order, method)
    raise ArgumentError, "Moyen d'encaissement inconnu : #{method}" unless METHODS.include?(method.to_s)

    attributes = { payment_status: :paid, offline_payment_method: method.to_s }
    attributes[:paid_at] = Time.current if order.read_attribute(:paid_at).blank?
    # Une commande `unpaid` (saisie en admin, party privée) affichait encore
    # « Non payée » une fois pointée : elle passe à `paid`, comme le fait déjà
    # « Marquer comme payée ». Une commande `ready` ou remise garde son statut —
    # `ready → paid` n'existe pas (#275). Les deux statuts sont dans le CA.
    attributes[:status] = :paid if order.unpaid?
    order.update!(attributes)

    # Une party privée réglée en liquide ou par virement n'a laissé aucune trace
    # automatique : ce pointage EST l'encaissement, et c'est donc ici que la
    # compta doit être prévenue (#289). Idempotent côté service : repointer
    # n'envoie pas un second e-mail.
    OrderNotificationService.send_party_accounting_notification(order)
  end

  # Annule le pointage (le boulanger s'est trompé de bouton). `paid_at` n'est
  # remis à nil que s'il n'existe aucune trace de paiement réelle — sinon on
  # effacerait une date qui ne vient pas du pointage.
  def self.clear!(order)
    attributes = { payment_status: :unpaid, offline_payment_method: nil }
    unless order.tracked_payment?
      attributes[:paid_at] = nil
      # Symétrique de `mark!` : sans argent tracé, une commande `paid` redevient due.
      attributes[:status] = :unpaid if order.paid?
    end
    order.update!(attributes)
  end
end
