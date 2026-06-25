# Prix coûtant d'une variante, historisé par date d'activation (#90).
# Les artisans saisissent manuellement un montant et une date à partir de
# laquelle ce coûtant s'applique. Le coûtant applicable à une date donnée est
# le palier le plus récent dont `active_from` est antérieure ou égale à la date
# (cf. ProductVariant#cost_price_cents). Versionnement par date : ajouter un
# nouveau palier ne modifie jamais le coûtant des périodes antérieures.
class VariantCostPrice < ApplicationRecord
  belongs_to :product_variant

  validates :amount_cents, presence: true, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :active_from, presence: true

  scope :ordered, -> { order(active_from: :desc, id: :desc) }

  def amount_euros
    return nil if amount_cents.nil?

    (amount_cents / 100.0).round(2)
  end

  def amount_euros=(value)
    self.amount_cents = value.to_s.strip.blank? ? nil : (value.to_s.tr(",", ".").to_f * 100).round
  end
end
