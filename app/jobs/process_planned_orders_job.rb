class ProcessPlannedOrdersJob < ApplicationJob
  include SlackNotifiable

  queue_as :default

  def perform
    @confirmed_count = 0
    @cancelled_count = 0
    @debited_cents = 0

    # Process every BakeDay whose cut-off has passed and that still has
    # planned orders to handle. The underlying service is idempotent
    # (it only touches Order.planned), so catching up on older cut-offs —
    # after a delayed run, restart, or incident — is safe and required
    # to avoid leaving orders stuck in the `planned` state.
    bake_days = BakeDay
                  .where("cut_off_at <= ?", Time.current)
                  .where(id: Order.planned.select(:bake_day_id))

    bake_days.find_each do |bake_day|
      Rails.logger.info("Processing planned orders for bake day #{bake_day.baked_on}")

      order_ids = Order.planned.where(bake_day: bake_day).pluck(:id)
      ProcessPlannedOrdersService.process_for_bake_day(bake_day)

      processed = Order.where(id: order_ids)
      @confirmed_count += processed.paid.count
      @cancelled_count += processed.cancelled.count
      @debited_cents   += processed.paid.sum(:total_cents)
    end
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
