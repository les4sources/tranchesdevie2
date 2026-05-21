class AuthMailer < ApplicationMailer
  # OTP login code delivered by email (fallback when SMS is not received).
  # OTP emails are always sent and never carry an unsubscribe link.
  def otp(customer, code)
    @customer = customer
    @code = code

    headers["X-Customer-Id"] = customer.id
    headers["X-Email-Kind"] = "otp"

    mail(to: customer.email, subject: "Ton code de connexion — Tranches de Vie")
  end
end
