# Mission Control Jobs configuration
# Protect the admin interface with HTTP Basic Auth

Rails.application.config.after_initialize do
  MissionControl::Jobs.http_basic_auth_enabled = true
  MissionControl::Jobs.http_basic_auth_user = ENV.fetch('ADMIN_USER', 'admin')
  MissionControl::Jobs.http_basic_auth_password = ENV['ADMIN_PASSWORD']

  if Rails.env.production? && ENV['ADMIN_PASSWORD'].blank?
    Rails.logger.warn "⚠️  ADMIN_PASSWORD is not set. Mission Control Jobs will be inaccessible."
  end
end
