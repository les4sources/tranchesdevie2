class RawMailer < ApplicationMailer
  # Re-delivers a previously logged email verbatim (admin "Renvoyer").
  # The stored body_html already contains the full layout, so we send it as a
  # single text/html part without re-applying the mailer layout.
  def resend(email_message)
    headers["X-Customer-Id"] = email_message.customer_id if email_message.customer_id
    headers["X-Email-Kind"] = email_message.kind
    headers["X-Order-Id"] = email_message.order_id if email_message.order_id

    mail(
      to: email_message.to_email,
      subject: email_message.subject,
      content_type: "text/html",
      body: email_message.body_html
    )
  end
end
