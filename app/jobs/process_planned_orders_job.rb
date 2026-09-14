class ProcessPlannedOrdersJob < ApplicationJob
  include SlackNotifiable

  queue_as :default

  def perform
    @confirmed_count = 0
    @cancelled_count = 0
    @debited_cents = 0

    self.class.pending_bake_days.find_each do |bake_day|
      Rails.logger.info("Processing planned orders for bake day #{bake_day.baked_on}")

      order_ids = Order.planned.where(bake_day: bake_day).pluck(:id)
      ProcessPlannedOrdersService.process_for_bake_day(bake_day)

      processed = Order.where(id: order_ids)
      @confirmed_count += processed.paid.count
      @cancelled_count += processed.cancelled.count
      @debited_cents   += processed.paid.sum(:total_cents)
    end
  end

  # Fournées dont le cut-off est passé et qui portent encore des commandes
  # `planned`. Le service sous-jacent est idempotent (il ne touche que
  # Order.planned) : rattraper des cut-offs plus anciens — après un run retardé,
  # un redémarrage ou un incident — est sûr, et nécessaire pour ne laisser
  # aucune commande coincée en `planned`.
  #
  # Depuis #274, le job passe tous les jours à 16h05 : ce scope est ce qui rend
  # le rythme quotidien sans effet les jours sans cut-off.
  def self.pending_bake_days
    BakeDay
      .where(cut_off_at: ..Time.current)
      .where(id: Order.planned.select(:bake_day_id))
  end

  private

  def slack_notification_summary
    return "Aucune commande planifiée à traiter." if @confirmed_count.zero? && @cancelled_count.zero?

    amount = format("%.2f", @debited_cents / 100.0)
    [
      "• #{@confirmed_count} commande(s) confirmée(s) (#{amount} € débités)",
      "• #{@cancelled_count} commande(s) annulée(s) (solde insuffisant)"
    ].join("\n")
  end
end
