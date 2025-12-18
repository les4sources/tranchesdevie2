class SmsService
  SMSTOOLS_API_URL = 'https://api.smsgatewayapi.com/v1/message/send'

  def self.send_confirmation(order)
    return false unless order.customer.sms_enabled?

    message = "Ta commande chez Tranches de Vie est confirmée. Merci !"
    send_sms(
      to: order.customer.phone_e164,
      body: message,
      kind: :confirmation,
      baked_on: order.bake_day.baked_on,
      customer_id: order.customer.id
    )
  end

  def self.send_ready(order)
    return false unless order.customer.sms_enabled?

    message = "Bonjour, ta commande est cuite, elle est disponible aux 4 Sources (Fonds d'Ahinvaux 1, Yvoir) ! Les artisans de Tranche de Vie"
    send_sms(
      to: order.customer.phone_e164,
      body: message,
      kind: :ready,
      baked_on: order.bake_day.baked_on,
      customer_id: order.customer.id
    )
  end

  def self.send_refund(order)
    return false unless order.customer.sms_enabled?

    message = "Ta commande a été remboursée intégralement car annulée avant l'heure limite."
    send_sms(
      to: order.customer.phone_e164,
      body: message,
      kind: :refund,
      baked_on: order.bake_day.baked_on,
      customer_id: order.customer.id
    )
  end

  def self.send_custom(customer, body)
    return false unless customer.sms_enabled?
    return false if body.blank?

    send_sms(
      to: customer.phone_e164,
      body: body,
      kind: :other,
      customer_id: customer.id
    )
  end

  private

  def self.send_sms(to:, body:, kind:, baked_on: nil, customer_id: nil)
    return false unless client_id && client_secret && sender

    # Format phone number: remove + if present (Smstools expects international format without +)
    formatted_to = to.to_s.gsub(/^\+/, '')

    # Use test mode in development (validates parameters but doesn't send SMS or consume credits)
    test_mode = !Rails.env.production?

    if test_mode
      Rails.logger.info("SMS (test mode in #{Rails.env}): To: #{formatted_to}, Body: #{body}")
    end

    response = HTTParty.post(
      SMSTOOLS_API_URL,
      headers: {
        'Content-Type' => 'application/json',
        'X-Client-Id' => client_id,
        'X-Client-Secret' => client_secret
      },
      body: {
        message: body,
        to: formatted_to,
        sender: sender,
        test: test_mode
      }.to_json
    )

    if response.success?
      # Smstools returns {"messageid": "..."} for single recipient
      external_id = response['messageid'] || (response['messageids']&.first)
      sent_at = Time.current
      SmsMessage.create!(
        direction: :outbound,
        to_e164: to,
        from_e164: sender,
        body: body,
        kind: kind,
        baked_on: baked_on,
        external_id: external_id,
        customer_id: customer_id,
        sent_at: sent_at
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

  def self.client_id
    ENV['SMSTOOLS_CLIENT_ID']
  end

  def self.client_secret
    ENV['SMSTOOLS_CLIENT_SECRET']
  end

  def self.sender
    ENV['SMSTOOLS_SENDER']
  end
end

