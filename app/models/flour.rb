# frozen_string_literal: true

class Flour < ApplicationRecord
  include HistorisedKiloPrice

  has_soft_deletion

  # Prix au kilo historisés par date d'effet (#209). L'ancienne colonne
  # `price_per_kg_cents` est conservée telle quelle (ses valeurs ont été
  # reprises comme premier palier par la migration), mais ce n'est plus elle
  # qui fait foi : `price_per_kg_cents_on(date)` interroge l'historique.
  has_kilo_price_history :flour_prices

  has_many :product_flours, dependent: :restrict_with_error

  # Levain associé à la farine (deux levains à la boulangerie : froment, seigle).
  enum :levain_type, { froment: "froment", seigle: "seigle" }

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validates :levain_type, presence: true
  validates :flour_ratio, :water_ratio, :salt_ratio, :levain_ratio,
            presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :price_per_kg_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  scope :ordered, -> { order(position: :asc, name: :asc) }
  scope :not_deleted, -> { where(deleted_at: nil) }

  # Les quatre ratios sont des fractions de la PÂTE (décision boulangers du
  # 25/08/2026) : leur somme vaut donc 1,0 pour une recette qui boucle
  # exactement. Au-dessus, l'écart est la marge de pétrissage (perte au
  # façonnage) ; en-dessous, la fournée manquera de matière. On affiche la
  # somme dans l'admin plutôt que de l'imposer — c'est un choix de boulanger.
  def panification_ratios_sum
    [ flour_ratio, water_ratio, salt_ratio, levain_ratio ].compact.sum
  end

  # Écart à 100 % de la pâte, en points de pourcentage (+5.5 = 5,5 % de marge).
  def panification_margin_percent
    ((panification_ratios_sum - 1) * 100).round(1)
  end

  # Prix affiché « aujourd'hui » : il vient désormais de l'historique, avec
  # repli sur l'ancienne colonne tant qu'aucun palier n'existe.
  def price_per_kg_euros
    from_history = price_per_kg_euros_on
    return from_history unless from_history.nil?
    return nil if price_per_kg_cents.nil?

    (price_per_kg_cents / 100.0).round(2)
  end

  def price_per_kg_euros=(value)
    self.price_per_kg_cents = value.to_s.strip.blank? ? nil : (value.to_s.tr(",", ".").to_f * 100).round
  end
end
