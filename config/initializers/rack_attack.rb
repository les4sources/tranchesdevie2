class Rack::Attack
  # Rate limit OTP requests (60s cooldown, max 5 attempts per phone)
  throttle('otp/phone', limit: 5, period: 60.seconds) do |req|
    if req.path == '/checkout/verify_phone' && req.post?
      req.params['phone_e164'] if req.params['phone_e164'].present?
    end
  end

  # Rate limit checkout init
  throttle('checkout/init', limit: 10, period: 60.seconds) do |req|
    req.ip if req.path == '/checkout' && req.post?
  end

  # Block requests from blocked IPs (if needed)
  # blocklist('block bad actors') do |req|
  #   Blocklist.find_by(ip: req.ip)
  # end
end

