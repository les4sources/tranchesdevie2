class MarkOrdersReadyJob < ApplicationJob
  queue_as :default

  def perform(date = nil)
    date ||= Date.current
    bake_day = BakeDay.find_by(baked_on: date)

    unless bake_day
      Rails.logger.info "No bake day found for #{date}, skipping mark orders ready job"
      return
    end

    orders_to_mark = bake_day.orders.where(status: [:paid, :unpaid])
    processed_count = 0
    error_count = 0

    orders_to_mark.find_each do |order|
      next unless order.can_transition_to?(:ready)

      begin
        order.transition_to!(:ready)
        SmsService.send_ready(order)
        processed_count += 1
      rescue StandardError => e
        error_count += 1
        Rails.logger.error "Failed to mark order #{order.id} as ready: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    Rails.logger.info "MarkOrdersReadyJob completed for #{date}: #{processed_count} orders marked as ready, #{error_count} errors"
  end
end

