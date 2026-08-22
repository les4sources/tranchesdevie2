# frozen_string_literal: true

# Coût d'un lieu de vente (#150), historisé par période de validité.
#
# Contrairement aux coûts historisés à date d'activation unique (VariantCostPrice,
# BreadBagPrice, RevenueParameter — où le palier le plus récent supersede les
# précédents), ce modèle porte une borne de fin explicite : `valid_until` nul =
# période EN COURS. Le coût applicable à une date est la période qui la couvre :
# `valid_from <= date` ET (`valid_until` nul OU `date <= valid_until`). En cas de
# chevauchement (déconseillé), la période au `valid_from` le plus récent gagne.
class SalesLocationCost < ApplicationRecord
  belongs_to :sales_location

  validates :amount_cents, presence: true,
                           numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :valid_from, presence: true
  validate :valid_until_after_valid_from

  # Plus récent d'abord : sert à la fois à l'affichage admin et à la résolution
  # du coût applicable (le premier qui couvre la date gagne).
  scope :ordered, -> { order(valid_from: :desc, id: :desc) }

  # Coût (cents) applicable à `on` pour `sales_location`, ou `nil` si aucune
  # période ne couvre la date. Requête bornée aux périodes ouvertes ou dont la
  # fin est postérieure/égale à la date.
  def self.cost_cents_for(sales_location, on: Date.current)
    sales_location
      .sales_location_costs
      .where(valid_from: ..on)
      .where("valid_until IS NULL OR valid_until >= ?", on)
      .ordered
      .limit(1)
      .pick(:amount_cents)
  end

  def amount_euros
    return nil if amount_cents.nil?

    (amount_cents / 100.0).round(2)
  end

  def amount_euros=(value)
    self.amount_cents = value.to_s.strip.blank? ? nil : (value.to_s.tr(",", ".").to_f * 100).round
  end

  private

  def valid_until_after_valid_from
    return if valid_until.blank? || valid_from.blank?
    return if valid_until >= valid_from

    errors.add(:valid_until, "doit être postérieure ou égale à la date de début")
  end
end
