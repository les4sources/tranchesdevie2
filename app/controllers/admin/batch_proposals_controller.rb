class Admin::BatchProposalsController < Admin::BaseController
  include Admin::BatchPlannerRendering

  before_action :set_bake_day

  # « Proposer une répartition » : remplace les fournées du jour par celle que
  # calculent les règles de Claire (`BatchPacker`). Les boulangers ajustent
  # ensuite à la main, avec les mêmes boutons qu'avant.
  def create
    count = BatchProposalService.new(@bake_day).apply!

    if count.zero?
      render_planner(notice: "Aucune ligne à répartir.")
    else
      render_planner(notice: "Répartition proposée en #{count} fournée#{'s' if count > 1}. Ajustez à la main si besoin.")
    end
  end
end
