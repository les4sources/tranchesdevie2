class ProcessPlannedOrdersJob < ApplicationJob
  queue_as :default

  def perform
    # Find BakeDays whose cut-off has just passed (within the last hour)
    # This job is scheduled to run just after cut-off times (18:05 on Sundays and Wednesdays)
    bake_days = BakeDay.where(cut_off_at: 1.hour.ago..Time.current)

    bake_days.find_each do |bake_day|
      Rails.logger.info("Processing planned orders for bake day #{bake_day.baked_on}")
      ProcessPlannedOrdersService.process_for_bake_day(bake_day)
    end
  end
end
