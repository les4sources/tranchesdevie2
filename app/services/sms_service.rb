class SmsService
  TELERIVET_API_URL = 'https://api.telerivet.com/v1'

  def self.send_confirmation(order)
    return false unless order.customer.sms_enabled?

    message = "Votre commande #{order.order_number} a été confirmée. Merci !"
    send_sms(
      to: order.customer.phone_e164,
      body: message,
      kind: :confirmation,
      baked_on: order.bake_day.baked_on
    )
  end

  def self.send_ready(order)
    return false unless order.customer.sms_enabled?

    message = "Bonjour, votre commande est cuite, elle est disponible aux 4 Sources ! Les artisans de Tranche de Vie"
    send_sms(
      to: order.customer.phone_e164,
      body: message,
      kind: :ready,
      baked_on: order.bake_day.baked_on
    )
  end

  def self.send_refund(order)
    return false unless order.customer.sms_enabled?

    message = "Votre commande a été remboursée intégralement car annulée avant l'heure limite."
    send_sms(
      to: order.customer.phone_e164,
      body: message,
      kind: :refund,
      baked_on: order.bake_day.baked_on
    )
  end

  private

  def self.send_sms(to:, body:, kind:, baked_on: nil)
    return false unless api_key && project_id && phone_id

    response = HTTParty.post(
      "#{TELERIVET_API_URL}/projects/#{project_id}/messages/send",
      headers: {
        'Content-Type' => 'application/json',
        'Authorization' => "Basic #{Base64.strict_encode64("#{api_key}:")}"
      },
      body: {
        to_number: to,
        content: body,
        phone_id: phone_id
      }.to_json
    )

    if response.success?
      external_id = response['id']
      SmsMessage.create!(
        direction: :outbound,
        to_e164: to,
        from_e164: phone_number,
        body: body,
        kind: kind,
        baked_on: baked_on,
        external_id: external_id
      )
      true
    else
      Rails.logger.error("Failed to send SMS: #{response.body}")
      false
    end
  rescue StandardError => e
    Rails.logger.error("SMS Service Error: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  def self.api_key
    ENV['TELERIVET_API_KEY']
  end

  def self.project_id
    ENV['TELERIVET_PROJECT_ID']
  end

  def self.phone_id
    ENV['TELERIVET_PHONE_ID']
  end

  def self.phone_number
    ENV['TELERIVET_PHONE_NUMBER'] || '+32XXXXXXXXX' # Should be set in ENV
  end
end

