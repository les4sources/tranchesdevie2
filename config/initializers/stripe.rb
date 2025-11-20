Stripe.api_key = ENV['STRIPE_SECRET_KEY']

if Rails.env.development? && ENV['STRIPE_SECRET_KEY'].blank?
  Rails.logger.warn "⚠️  STRIPE_SECRET_KEY is not set. Stripe operations will fail."
end

if Rails.env.production?
  if ENV['STRIPE_SECRET_KEY'].blank?
    raise "STRIPE_SECRET_KEY must be set in production"
  end
  if ENV['STRIPE_PUBLIC_KEY'].blank?
    raise "STRIPE_PUBLIC_KEY must be set in production"
  end
  if ENV['STRIPE_WEBHOOK_SECRET'].blank?
    Rails.logger.warn "⚠️  STRIPE_WEBHOOK_SECRET is not set. Webhook signature verification will fail."
  end
end
