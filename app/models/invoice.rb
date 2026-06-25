# Facture client (#38).
#
# Une facture couvre soit **une seule commande**, soit **un ensemble de
# commandes** (période — facture mensuelle groupée des clients pro). Les
# commandes couvertes sont liées via `invoice_orders`.
#
# Numérotation **séquentielle annuelle** : « FAC-YYYY-NNNN » (unique). La
# séquence repart à 1 chaque année civile.
#
# Montants figés à l'émission (en cents) : `subtotal_cents` (HT), `vat_cents`
# (TVA), `total_cents` (TTC). La TVA est **paramétrable** (note TVA #38) : taux
# 0 par défaut → HT == TTC, ce qui ne bloque jamais la génération.
class Invoice < ApplicationRecord
  NUMBER_PREFIX = "FAC".freeze
  NUMBER_FORMAT = /\A#{NUMBER_PREFIX}-\d{4}-\d{4}\z/

  belongs_to :customer
  has_many :invoice_orders, dependent: :destroy
  has_many :orders, through: :invoice_orders

  validates :number, presence: true, uniqueness: true, format: { with: NUMBER_FORMAT }
  validates :issued_on, presence: true
  validates :subtotal_cents, :vat_cents, :total_cents,
            presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :vat_rate, presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validate :period_consistency

  before_validation :assign_number, on: :create

  scope :recent, -> { order(issued_on: :desc, id: :desc) }

  # Construit (sans sauvegarder) une facture pour une commande unique, avec ses
  # montants calculés selon le taux de TVA fourni (défaut : réglage boulangerie).
  def self.build_for_order(order, issued_on: Date.current, vat_rate: BakeryDetails.default_vat_rate)
    invoice = new(
      customer: order.customer,
      issued_on: issued_on,
      vat_rate: vat_rate
    )
    invoice.invoice_orders.build(order: order)
    invoice.assign_amounts_from([ order ])
    invoice
  end

  # Construit (sans sauvegarder) une facture de période pour un client, couvrant
  # les commandes fournies (déjà filtrées par l'appelant — typiquement le mois).
  def self.build_for_period(customer:, orders:, period_start:, period_end:,
                            issued_on: Date.current, vat_rate: BakeryDetails.default_vat_rate)
    invoice = new(
      customer: customer,
      issued_on: issued_on,
      period_start: period_start,
      period_end: period_end,
      vat_rate: vat_rate
    )
    orders.each { |order| invoice.invoice_orders.build(order: order) }
    invoice.assign_amounts_from(orders)
    invoice
  end

  # (Re)calcule et affecte les montants HT/TVA/TTC à partir des commandes.
  # Les totaux des commandes (`total_cents`) sont considérés TTC : on en déduit
  # le HT et la TVA selon le taux. Avec un taux à 0, HT == TTC.
  def assign_amounts_from(orders)
    ttc = orders.sum(&:total_cents)
    rate = (vat_rate || 0).to_d

    self.total_cents = ttc
    self.subtotal_cents = (ttc / (1 + rate / 100)).round
    self.vat_cents = ttc - subtotal_cents
    self
  end

  # Facture portant sur une seule commande ?
  def single_order?
    period_start.blank? && period_end.blank?
  end

  # Facture de période (mensuelle groupée) ?
  def period?
    !single_order?
  end

  def subtotal_euros
    subtotal_cents / 100.0
  end

  def vat_euros
    vat_cents / 100.0
  end

  def total_euros
    total_cents / 100.0
  end

  # TVA effectivement appliquée (au-delà de 0) ?
  def vat_applied?
    vat_rate.to_d.positive? && vat_cents.positive?
  end

  private

  # Attribue le prochain numéro séquentiel pour l'année d'émission.
  # Concurrence : la contrainte d'unicité sur `number` protège en dernier
  # recours ; un éventuel doublon lève une erreur plutôt que d'attribuer un
  # numéro dupliqué silencieusement.
  def assign_number
    return if number.present?

    year = (issued_on || Date.current).year
    self.number = self.class.next_number_for(year)
  end

  def self.next_number_for(year)
    prefix = "#{NUMBER_PREFIX}-#{year}-"
    last = where("number LIKE ?", "#{prefix}%").order(:number).last
    sequence = if last && (match = last.number.match(/-(\d{4})\z/))
                 match[1].to_i + 1
    else
                 1
    end
    "#{prefix}#{sequence.to_s.rjust(4, '0')}"
  end

  def period_consistency
    return if period_start.blank? && period_end.blank?

    if period_start.blank? || period_end.blank?
      errors.add(:base, "La période doit avoir une date de début et de fin")
    elsif period_end < period_start
      errors.add(:period_end, "doit être postérieure à la date de début")
    end
  end
end
