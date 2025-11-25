class BakeDaySlackNotificationJob < ApplicationJob
  queue_as :default

  def perform(date = nil)
    date ||= Date.current
    bake_day = BakeDay.find_by(baked_on: date)

    return unless bake_day

    breads_count = bake_day.total_breads_count
    total_sales = bake_day.total_sales_euros

    message = "Salut, ce sont les boulangers. Aujourd'hui on va produire #{breads_count} pains, pour un total de #{total_sales.round(2)} € de ventes. N'hésitez pas à passer nous faire coucou à la cuisine !"

    SlackService.send_message(message)
  rescue SlackService::Error => e
    Rails.logger.error "Failed to send Slack notification for bake day #{date}: #{e.message}"
    raise
  end
end

