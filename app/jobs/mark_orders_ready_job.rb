class MarkOrdersReadyJob < ApplicationJob
  include SlackNotifiable

  queue_as :default

  def perform(date = nil)
    date ||= Date.current
    @date = date
    @processed_count = 0
    @error_count = 0
    @bake_day_found = false

    bake_day = BakeDay.find_by(baked_on: date)

    unless bake_day
      Rails.logger.info "No bake day found for #{date}, skipping mark orders ready job"
      return
    end

    @bake_day_found = true
    orders_to_mark = bake_day.orders.where(status: [ :paid, :unpaid ])

    orders_to_mark.find_each do |order|
      next unless order.can_transition_to?(:ready)

      begin
        order.transition_to!(:ready)
        SmsService.send_ready(order)
        @processed_count += 1
      rescue StandardError => e
        @error_count += 1
        Rails.logger.error "Failed to mark order #{order.id} as ready: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end

    Rails.logger.info "MarkOrdersReadyJob completed for #{date}: #{@processed_count} orders marked as ready, #{@error_count} errors"
  end

  private

  def slack_notification_summary
    return "Aucun bake day trouvé pour #{@date}." unless @bake_day_found

    summary = "• #{@processed_count} commande(s) marquée(s) prête(s) pour le #{@date}"
    summary += "\n• #{@error_count} erreur(s)" if @error_count.positive?
    summary
  end
end
