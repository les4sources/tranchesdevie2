# Configure session to persist for 1 year
Rails.application.config.session_store :cookie_store,
  key: '_tranchesdevie2_session',
  expire_after: 1.year,
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax

# Ensure session cookies persist across browser restarts
Rails.application.config.action_dispatch.cookies_serializer = :json

