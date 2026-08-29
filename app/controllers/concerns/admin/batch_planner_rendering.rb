# frozen_string_literal: true

module Admin
  # Toutes les actions du calculateur de fournées (#194) répondent la même
  # chose : le planificateur recalculé. Les boulangers cochent les mains dans la
  # farine — aucune action ne doit recharger la page ni demander « Enregistrer ».
  module BatchPlannerRendering
    extend ActiveSupport::Concern

    private

    def set_bake_day
      @bake_day = BakeDay.find(params[:bake_day_id])
    end

    def render_planner(notice: nil)
      @dashboard = Admin::BakeDayDashboard.new(@bake_day)
      @planner = Admin::BatchPlanner.new(@bake_day, @dashboard)
      @planner_notice = notice

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "batch-planner",
            partial: "admin/bake_days/batches/planner",
            locals: { bake_day: @bake_day, planner: @planner, notice: notice }
          )
        end
        format.html { redirect_to admin_bake_day_path(@bake_day), notice: notice }
      end
    end
  end
end
