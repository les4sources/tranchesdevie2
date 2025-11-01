Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN'] if ENV['SENTRY_DSN'].present?
  config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  
  # Filter sensitive data
  config.before_send = lambda do |event, hint|
    # Mask phone numbers in logs
    if event.message
      event.message = event.message.gsub(/\+\d{10,15}/, '[PHONE_MASKED]')
    end
    event
  end

  # Set traces sample rate
  config.traces_sample_rate = ENV.fetch('SENTRY_TRACES_SAMPLE_RATE', '0.1').to_f

  # Environment
  config.environment = Rails.env
end if ENV['SENTRY_DSN'].present?

