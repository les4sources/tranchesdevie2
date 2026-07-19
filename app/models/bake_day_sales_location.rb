# frozen_string_literal: true

# Jointure entre un jour de cuisson et un lieu de vente (#150). La présence d'une
# ligne signifie que la fournée a été vendue sur ce lieu — dont le coût du jour
# est déduit de la marge brute (cf. BakerRevenueService).
class BakeDaySalesLocation < ApplicationRecord
  belongs_to :bake_day
  belongs_to :sales_location
end
