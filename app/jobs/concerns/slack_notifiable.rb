module SlackNotifiable
  extend ActiveSupport::Concern

  included do
    around_perform :notify_slack_around_perform
  end

  private

  def notify_slack_around_perform
    started_at = Time.current
    error = nil

    begin
      yield
    rescue StandardError => e
      error = e
      raise
    ensure
      duration_s = (Time.current - started_at).round(2)
      send_slack_notification(duration_s: duration_s, error: error)
    end
  end

  def send_slack_notification(duration_s:, error:)
    text =
      if error
        ":x: *#{self.class.name}* a échoué après #{duration_s}s\n" \
        "`#{error.class}`: #{error.message}"
      else
        summary = slack_notification_summary
        header = ":white_check_mark: *#{self.class.name}* — OK en #{duration_s}s"
        summary.present? ? "#{header}\n#{summary}" : header
      end

    SlackService.send_message(text)
  rescue StandardError => e
    Rails.logger.warn("Slack notification failed for #{self.class.name}: #{e.message}")
  end

  # Override in each job to provide a business summary.
  def slack_notification_summary
    nil
  end
end
