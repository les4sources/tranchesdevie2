class CheckInsufficientBalanceJob < ApplicationJob
  include SlackNotifiable

  queue_as :default

  # Préavis de l'alerte « solde insuffisant » : on ne regarde que les fournées
  # dont le cut-off tombe dans les 4 heures. Nommé plutôt qu'écrit en dur, parce
  # que cette fenêtre et l'heure du cron (08h00, cf. config/recurring.yml) ne se
  # comprennent que l'une par l'autre : 08h00 + 4 h = le cut-off de 12h00 (#292).
  WARNING_LEAD = 4.hours

  def perform
    @checked_count = 0
    @warned_count = 0

    # Fournées dont le cut-off tombe dans WARNING_LEAD. Le job passe tous les
    # jours à 08h00 (#274, recalé en #292) — quatre heures avant un cut-off à
    # 12h00 — et cette fenêtre le rend sans effet les jours sans cut-off.
    upcoming_cutoffs = BakeDay.where(cut_off_at: Time.current..WARNING_LEAD.from_now)

    upcoming_cutoffs.find_each do |bake_day|
      Rails.logger.info("Checking insufficient balances for bake day #{bake_day.baked_on}")

      Order.planned.where(bake_day: bake_day).includes(:customer).find_each do |order|
        @checked_count += 1
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
        @warned_count += 1
        Rails.logger.info("Sent insufficient balance warning for order #{order.id}")
      end
    end
  rescue StandardError => e
    Rails.logger.error("Error checking balance for order #{order.id}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def slack_notification_summary
    return "Aucune commande planifiée à vérifier." if @checked_count.zero?

    "• #{@checked_count} commande(s) vérifiée(s)\n" \
      "• #{@warned_count} client(s) alerté(s) pour solde insuffisant"
  end
end
