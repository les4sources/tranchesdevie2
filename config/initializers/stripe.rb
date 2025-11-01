Stripe.api_key = ENV['STRIPE_SECRET_KEY']

if Rails.env.development? && ENV['STRIPE_SECRET_KEY'].blank?
  Rails.logger.warn "⚠️  STRIPE_SECRET_KEY is not set. Stripe operations will fail."
end

