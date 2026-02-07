class SmsService
  extend ActionView::Helpers::NumberHelper

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
    # si la commande n'est pas payée, on envoie un message différent
    if order.unpaid_ready?
      amount_formatted = number_to_currency(order.total_euros, unit: "€", separator: ",", delimiter: "").gsub(",00", "")
      message = "Bonjour, ta commande de pains est prête, elle est disponible dans l'épicerie aux 4 Sources (Fonds d'Ahinvaux 1, Yvoir) ! Si tu paies sur place (#{amount_formatted}), merci de la noter dans le carnet près du rack. Les artisans de Tranche de Vie"
    else
      message = "Bonjour, ta commande de pains est prête, elle est disponible dans l'épicerie aux 4 Sources (Fonds d'Ahinvaux 1, Yvoir) ! Les artisans de Tranche de Vie"
    end
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
    unless client_id.present? && client_secret.present? && sender.present?
      Rails.logger.error("SMS Service - Missing configuration: client_id=#{client_id.present?}, client_secret=#{client_secret.present?}, sender=#{sender.present?}")
      return false
    end

    # Format phone number: remove + if present (Smstools expects international format without +)
    formatted_to = to.to_s.gsub(/^\+/, '')

    # Use test mode in development (validates parameters but doesn't send SMS or consume credits)
    test_mode = !Rails.env.production?

    # Log request details
    Rails.logger.info("SMS Service (#{Rails.env}): To: #{formatted_to}, Sender: #{sender}, Test: #{test_mode}, Kind: #{kind}")
    Rails.logger.debug("SMS Service - Client ID present: #{client_id.present?}, Client Secret present: #{client_secret.present?}, Sender present: #{sender.present?}")

    request_body = {
      message: body,
      to: formatted_to,
      sender: sender,
      test: test_mode
    }

    response = HTTParty.post(
      SMSTOOLS_API_URL,
      headers: {
        'Content-Type' => 'application/json',
        'X-Client-Id' => client_id,
        'X-Client-Secret' => client_secret
      },
      body: request_body.to_json
    )

    Rails.logger.info("SMS Service - Response status: #{response.code}, Success: #{response.success?}")
    Rails.logger.debug("SMS Service - Response body: #{response.body}")

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
      Rails.logger.info("SMS Service - SMS sent successfully. External ID: #{external_id}")
      true
    else
      Rails.logger.error("Failed to send SMS - Status: #{response.code}, Body: #{response.body}, Request: #{request_body.inspect}")
      false
    end
  rescue StandardError => e
    Rails.logger.error("SMS Service Error: #{e.class} - #{e.message}")
    Rails.logger.error("SMS Service Error Backtrace: #{e.backtrace.first(5).join("\n")}")
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

