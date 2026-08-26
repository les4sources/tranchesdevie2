class Admin::EmailMessagesController < Admin::BaseController
  before_action :set_customer
  before_action :set_email_message

  def show
    render json: {
      id: @email_message.id,
      subject: @email_message.subject,
      to_email: @email_message.to_email,
      from_email: @email_message.from_email,
      kind: @email_message.kind,
      sent_at: (@email_message.sent_at || @email_message.created_at).strftime("%d/%m/%Y à %H:%M"),
      body_html: @email_message.body_html
    }
  end

  def resend
    if @email_message.to_email.blank?
      render json: { success: false, error: "Adresse e-mail manquante" }, status: :unprocessable_entity
      return
    end

    RawMailer.resend(@email_message).deliver_now
    render json: { success: true, message: "E-mail renvoyé avec succès" }
  rescue StandardError => e
    Rails.logger.error("Error resending email: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    render json: { success: false, error: "Erreur lors du renvoi de l'e-mail" }, status: :unprocessable_entity
  end

  private

  def set_customer
    @customer = Customer.find(params[:customer_id])
  end

  def set_email_message
    @email_message = @customer.email_messages.find(params[:id])
  end
end
