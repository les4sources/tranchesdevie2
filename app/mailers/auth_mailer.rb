class AuthMailer < ApplicationMailer
  # OTP login code delivered by email (fallback when SMS is not received).
  # OTP emails are always sent and never carry an unsubscribe link.
  # `email` is the recipient; `customer` is optional (nil for an unregistered phone).
  def otp(email, code, customer: nil)
    @customer = customer
    @code = code

    headers["X-Customer-Id"] = customer.id if customer
    headers["X-Email-Kind"] = "otp"

    mail(to: email, subject: "Ton code de connexion — Tranches de Vie")
  end
end
