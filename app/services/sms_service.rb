class SmsService
  extend ActionView::Helpers::NumberHelper

  def self.send_confirmation(order)
    return false unless order.customer.sms_enabled?

    deliver(
      template_name: :confirmation,
      to: order.customer.phone_e164,
      kind: :confirmation,
      bake_day: order.bake_day,
      customer: order.customer
    )
  end

  def self.send_ready(order)
    return false unless order.customer.sms_enabled?

    template_name = order.unpaid_ready? ? :ready_unpaid : :ready_paid
    parameters = order.unpaid_ready? ? { amount: format_amount(order.total_euros) } : {}

    deliver(
      template_name: template_name,
      to: order.customer.phone_e164,
      parameters: parameters,
      kind: :ready,
      bake_day: order.bake_day,
      customer: order.customer
    )
  end

  def self.send_refund(order)
    return false unless order.customer.sms_enabled?

    deliver(
      template_name: :refund,
      to: order.customer.phone_e164,
      kind: :refund,
      bake_day: order.bake_day,
      customer: order.customer
    )
  end

  def self.send_planned_order_confirmed(order)
    return false unless order.customer.sms_enabled?

    deliver(
      template_name: :planned_confirmed,
      to: order.customer.phone_e164,
      parameters: {
        bake_date: I18n.l(order.bake_day.baked_on, format: :long),
        amount: format_amount(order.total_euros)
      },
      kind: :confirmation,
      bake_day: order.bake_day,
      customer: order.customer
    )
  end

  def self.send_planned_order_cancelled(order)
    return false unless order.customer.sms_enabled?

    deliver(
      template_name: :planned_cancelled,
      to: order.customer.phone_e164,
      parameters: { bake_date: I18n.l(order.bake_day.baked_on, format: :long) },
      kind: :other,
      bake_day: order.bake_day,
      customer: order.customer
    )
  end

  def self.send_low_balance_alert(customer)
    return false unless customer.sms_enabled?

    wallet = customer.wallet
    return false unless wallet

    deliver(
      template_name: :low_balance,
      to: customer.phone_e164,
      parameters: { balance: format_amount(wallet.balance_euros) },
      kind: :other,
      customer: customer
    )
  end

  def self.send_insufficient_balance_warning(order)
    return false unless order.customer.sms_enabled?

    wallet = order.customer.wallet
    amount_needed = order.total_cents - (wallet&.balance_cents || 0)

    deliver(
      template_name: :insufficient_balance,
      to: order.customer.phone_e164,
      parameters: {
        amount_needed: format_amount(amount_needed / 100.0),
        bake_date: I18n.l(order.bake_day.baked_on, format: :long)
      },
      kind: :other,
      bake_day: order.bake_day,
      customer: order.customer
    )
  end

  def self.deliver(template_name:, to:, parameters: {}, kind:, customer:, bake_day: nil)
    response = SentDmClient.send_message(
      template_name: template_name,
      to: to,
      parameters: parameters
    )

    body = response&.data&.recipients&.first&.body || rendered_body(template_name, parameters)
    external_id = response&.data&.recipients&.first&.message_id

    SmsMessage.create!(
      direction: :outbound,
      to_e164: to,
      from_e164: sender,
      body: body,
      kind: kind,
      baked_on: bake_day&.baked_on,
      external_id: external_id,
      customer_id: customer&.id,
      sent_at: Time.current
    )
    true
  rescue StandardError => e
    Rails.logger.error("SmsService - échec envoi #{template_name} à #{to}: #{e.class} #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  def self.rendered_body(template_name, parameters)
    template = SmsTemplate.find_by(name: template_name.to_s)
    return nil unless template
    body = template.body
    parameters.each do |key, value|
      body = body.gsub(/\{\{\d+:#{Regexp.escape(key.to_s)}\}\}/, value.to_s)
    end
    body
  end

  def self.format_amount(amount_euros)
    number_to_currency(amount_euros, unit: "€", separator: ",", delimiter: "").gsub(",00", "")
  end

  def self.sender
    ENV.fetch("SENT_DM_SENDER_ID", "LES4SOURCES")
  end
end
