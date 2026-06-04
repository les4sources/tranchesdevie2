class Rack::Attack
  # Rack::Attack stocke ses compteurs dans Rails.cache par défaut. En production,
  # Rails.cache est Solid Cache (table solid_cache_entries), qui n'est pas
  # provisionnée ici — et aucune autre partie de l'app n'utilise Rails.cache.
  # On découple donc le rate-limiting avec un store mémoire dédié (par process),
  # suffisant pour la protection anti-abus et sans dépendance à une table cache.
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new if Rails.env.production?

  # Rate limit OTP requests (60s cooldown, max 5 attempts per phone)
  throttle("otp/phone", limit: 5, period: 60.seconds) do |req|
    if req.path == "/checkout/verify_phone" && req.post?
      req.params["phone_e164"] if req.params["phone_e164"].present?
    end
  end

  # Rate limit login OTP *sends* per identifier (phone OR email). Only the send
  # step counts (no otp_code); code verification has its own attempts cap.
  throttle("login-otp/identifier", limit: 5, period: 60.seconds) do |req|
    if req.path == "/connexion" && req.post? && req.params["otp_code"].blank?
      identifier = req.params["identifier"].presence || req.params["phone_e164"]
      identifier.to_s.strip.downcase if identifier.present?
    end
  end

  # Rate limit login OTP sends per IP. The email channel can target an arbitrary
  # address, so cap how many a single IP can trigger.
  throttle("login-otp/ip", limit: 8, period: 60.seconds) do |req|
    req.ip if req.path == "/connexion" && req.post? && req.params["otp_code"].blank?
  end

  # Rate limit checkout init
  throttle("checkout/init", limit: 10, period: 60.seconds) do |req|
    req.ip if req.path == "/checkout" && req.post?
  end

  # Rate limit OTP sends per IP. The email channel can target an arbitrary
  # address (unregistered phones), so cap how many a single IP can trigger.
  throttle("otp-send/ip", limit: 8, period: 60.seconds) do |req|
    req.ip if req.path == "/checkout/verify_phone" && req.post?
  end

  # Block requests from blocked IPs (if needed)
  # blocklist('block bad actors') do |req|
  #   Blocklist.find_by(ip: req.ip)
  # end
end
