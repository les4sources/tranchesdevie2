class ProcessPlannedOrdersJob < ApplicationJob
  queue_as :default

  def perform
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
      ProcessPlannedOrdersService.process_for_bake_day(bake_day)
    end
  end
end
