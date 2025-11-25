class SlackService
  class Error < StandardError; end

  def self.send_message(text, webhook_url: nil)
    new(webhook_url: webhook_url).send_message(text)
  end

  def initialize(webhook_url: nil)
    @webhook_url = webhook_url || ENV['SLACK_WEBHOOK_URL']
    raise Error, 'SLACK_WEBHOOK_URL environment variable is not set' if @webhook_url.blank?
  end

  def send_message(text)
    response = HTTParty.post(
      @webhook_url,
      body: {
        text: text
      }.to_json,
      headers: {
        'Content-Type' => 'application/json'
      }
    )

    unless response.success?
      raise Error, "Failed to send Slack message: #{response.code} - #{response.body}"
    end

    response
  rescue HTTParty::Error => e
    raise Error, "HTTP error while sending Slack message: #{e.message}"
  end
end

