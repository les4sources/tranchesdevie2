class Admin::BatchesController < Admin::BaseController
  include Admin::BatchPlannerRendering

  before_action :set_bake_day
  before_action :set_batch, only: [ :update, :destroy ]

  def create
    @bake_day.batches.create!(
      name: Batch.next_default_name(@bake_day),
      position: Batch.next_position(@bake_day)
    )

    render_planner(notice: "Fournée ajoutée.")
  end

  def update
    if @batch.update(batch_params)
      render_planner(notice: "Fournée renommée.")
    else
      render_planner(notice: @batch.errors.full_messages.to_sentence)
    end
  end

  # Supprimer une fournée ne détruit AUCUNE ligne de commande : `dependent:
  # :nullify` les renvoie dans « non affectées », où elles restent visibles.
  def destroy
    name = @batch.name
    @batch.destroy!

    render_planner(notice: "#{name} supprimée — ses lignes sont redevenues non affectées.")
  end

  private

  def set_batch
    @batch = @bake_day.batches.find(params[:id])
  end

  def batch_params
    params.require(:batch).permit(:name)
  end
end
