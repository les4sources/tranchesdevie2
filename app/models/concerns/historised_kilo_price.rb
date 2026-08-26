# frozen_string_literal: true

# Résolution d'un prix au kilo historisé par date d'effet (#209).
#
# Le prix applicable à une date est le palier le plus récent dont `active_from`
# est antérieure OU ÉGALE à cette date — borne incluse, comme
# `RevenueParameter.value_on` et `ProductVariant#cost_price_cents`.
#
# Avant tout palier, la réponse est `nil` et non zéro : un prix inconnu n'est
# pas un prix nul. Les appelants décident quoi en faire, et l'écran de coûts le
# signale explicitement plutôt que d'afficher un total faussement rassurant.
module HistorisedKiloPrice
  extend ActiveSupport::Concern

  class_methods do
    # `has_kilo_price_history :ingredient_prices` — installe l'association et
    # les résolveurs sur le modèle porteur.
    def has_kilo_price_history(association)
      has_many association, dependent: :destroy

      define_method(:kilo_prices) { public_send(association) }
    end
  end

  # Prix au kilo (cents) applicable à `date`, ou nil si aucun palier ne la
  # couvre.
  def price_per_kg_cents_on(date = Date.current)
    kilo_prices.where(active_from: ..date).order(active_from: :desc, id: :desc).limit(1).pick(:amount_cents)
  end

  def price_per_kg_euros_on(date = Date.current)
    cents = price_per_kg_cents_on(date)
    return nil if cents.nil?

    (cents / 100.0).round(2)
  end

  # Y a-t-il au moins un palier ? Sert à distinguer « pas encore de prix » de
  # « prix nul » dans les écrans.
  def priced?
    kilo_prices.exists?
  end
end
