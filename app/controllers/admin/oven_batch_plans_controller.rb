class Admin::OvenBatchPlansController < Admin::BaseController
  before_action :set_bake_day

  # Décision des boulangers face à l'alerte « Capacité four » : rester à deux
  # fournées pleines ou ouvrir une 3e fournée. Réversible dans les deux
  # sens, tant que le pain tient dans deux fournées pour revenir à deux.
  def update
    plan = params[:plan].to_i

    unless [ OvenBatchAlert::DEFAULT_BATCHES, OvenBatchAlert::THIRD_BATCH ].include?(plan)
      return redirect_to admin_bake_day_path(@bake_day), alert: "Choix de fournées inconnu.", status: :see_other
    end

    if plan == OvenBatchAlert::DEFAULT_BATCHES && !OvenBatchAlert.for(@bake_day).two_batches_possible?
      return redirect_to admin_bake_day_path(@bake_day), alert: "Le four dépasse déjà #{OvenBatchAlert::TWO_BATCHES_KG} kg : deux fournées ne suffisent plus.", status: :see_other
    end

    @bake_day.update!(oven_batch_plan: plan, oven_batch_plan_decided_at: Time.current)

    notice =
      if plan == OvenBatchAlert::THIRD_BATCH
        "3e fournée ouverte : l'horaire de production s'allonge."
      else
        "Deux fournées pleines validées : jusqu'à #{OvenBatchAlert::TWO_BATCHES_KG} kg de pain au four."
      end

    redirect_to admin_bake_day_path(@bake_day), notice: notice, status: :see_other
  end

  private

  def set_bake_day
    @bake_day = BakeDay.find(params[:bake_day_id])
  end
end
