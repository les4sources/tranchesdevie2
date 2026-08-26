# frozen_string_literal: true

# Répartition de la recette des ATELIERS (#208).
#
# Règle appliquée, et ses limites :
#
#   part 4 Sources  = recette × taux 4S ateliers (paramètre historisé)
#   part boulangers = recette − part 4 Sources
#
# Le partage 70/30 des pains ne s'applique PAS mécaniquement ici : un atelier
# n'a ni coûtant matière, ni sacs, ni transport, ni commission — il n'y a pas de
# « marge brute » à partager, seulement une recette. Le taux est donc un
# paramètre propre aux ateliers, distinct de celui de la production.
#
# **Ce taux n'a pas été tranché en réunion.** Tant qu'aucun palier n'est saisi,
# `RevenueParameter.workshop_basis_points_on` renvoie `nil` et l'atelier est
# marqué NON RÉPARTI : sa recette est affichée, mais elle ne verse rien à
# personne. On préfère un trou visible à un chiffre deviné.
#
# La part boulangers, une fois calculée, passe par le MÊME chemin que la
# production : une part par artisan animateur au pourcentage configuré
# (`ArtisanRevenueShare`), puis mutualisation par partenariat en aval
# (`BakerRevenueService#build_settlements`). Rien n'est réimplémenté.
class WorkshopRevenueService
  Breakdown = Struct.new(
    :workshop,
    :date,
    :revenue_cents,
    :four_sources_cents,
    :bakers_cents,
    :artisan_shares,
    :rate_basis_points,   # nil = répartition non tranchée
    :unassigned,          # aucun animateur sélectionné
    keyword_init: true
  ) do
    def distributed? = !rate_basis_points.nil? && !unassigned
    def rate_undefined? = rate_basis_points.nil?
    def revenue_euros = (revenue_cents / 100.0).round(2)
  end

  Result = Struct.new(:workshops, :total_revenue_cents, :total_four_sources_cents,
                      :total_bakers_cents, :undistributed_count, keyword_init: true)

  ArtisanShare = BakerRevenueService::ArtisanShare

  def self.call(workshops)
    new(workshops).call
  end

  def initialize(workshops)
    @workshops = workshops.to_a
  end

  def call
    breakdowns = @workshops.map { |workshop| build(workshop) }

    Result.new(
      workshops: breakdowns,
      total_revenue_cents: breakdowns.sum(&:revenue_cents),
      total_four_sources_cents: breakdowns.sum(&:four_sources_cents),
      total_bakers_cents: breakdowns.sum(&:bakers_cents),
      undistributed_count: breakdowns.count { |b| !b.distributed? }
    )
  end

  private

  def build(workshop)
    date = workshop.held_on
    rate = RevenueParameter.workshop_basis_points_on(date)
    artisans = workshop.artisans.to_a
    unassigned = artisans.empty?

    # Deux raisons de ne rien répartir : le taux n'est pas tranché, ou personne
    # n'anime. Dans les deux cas la recette est conservée et affichée, mais
    # aucune part n'est versée.
    if rate.nil? || unassigned
      return Breakdown.new(
        workshop: workshop, date: date, revenue_cents: workshop.revenue_cents,
        four_sources_cents: 0, bakers_cents: 0, artisan_shares: [],
        rate_basis_points: rate, unassigned: unassigned
      )
    end

    four_sources_cents = (workshop.revenue_cents * rate / 10_000.0).round
    bakers_cents = workshop.revenue_cents - four_sources_cents

    Breakdown.new(
      workshop: workshop,
      date: date,
      revenue_cents: workshop.revenue_cents,
      four_sources_cents: four_sources_cents,
      bakers_cents: bakers_cents,
      artisan_shares: shares_for(artisans, bakers_cents, date),
      rate_basis_points: rate,
      unassigned: false
    )
  end

  # Strictement le même calcul que `BakerRevenueService#artisan_shares` : une
  # part par animateur, au pourcentage littéral configuré à la date.
  def shares_for(artisans, pool_cents, date)
    artisans.map do |artisan|
      percent = artisan.revenue_share_percent(on: date)
      amount = percent.nil? ? 0 : (pool_cents * percent / 100.0).round

      ArtisanShare.new(artisan: artisan, percent: percent, amount_cents: amount)
    end
  end
end
