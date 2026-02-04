class CheckInsufficientBalanceJob < ApplicationJob
  queue_as :default

  def perform
    # Find BakeDays with upcoming cut-offs (within the next 6 hours)
    # This job is scheduled to run at noon on Sundays and Wednesdays
    upcoming_cutoffs = BakeDay.where(cut_off_at: Time.current..6.hours.from_now)

    upcoming_cutoffs.find_each do |bake_day|
      Rails.logger.info("Checking insufficient balances for bake day #{bake_day.baked_on}")

      Order.planned.where(bake_day: bake_day).includes(:customer).find_each do |order|
        check_and_notify(order)
      end
    end
  end

  private

  def check_and_notify(order)
    wallet = order.customer.wallet

    if wallet.nil? || !wallet.can_cover?(order.total_cents)
      # Only send if we haven't already warned recently (avoid spam)
      last_warning = SmsMessage.where(customer_id: order.customer.id, kind: :other)
                               .where("body LIKE ?", "%manque%")
                               .where("sent_at > ?", 24.hours.ago)
                               .exists?

      unless last_warning
        SmsService.send_insufficient_balance_warning(order)
        Rails.logger.info("Sent insufficient balance warning for order #{order.id}")
      end
    end
  rescue StandardError => e
    Rails.logger.error("Error checking balance for order #{order.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end
end
