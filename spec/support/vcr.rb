require 'vcr'
require 'webmock/rspec'

VCR.configure do |config|
  config.cassette_library_dir = 'spec/cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Filter sensitive data
  config.filter_sensitive_data('<STRIPE_SECRET_KEY>') { ENV['STRIPE_SECRET_KEY'] }
  config.filter_sensitive_data('<STRIPE_WEBHOOK_SECRET>') { ENV['STRIPE_WEBHOOK_SECRET'] }
  config.filter_sensitive_data('<SMSTOOLS_CLIENT_ID>') { ENV['SMSTOOLS_CLIENT_ID'] }
  config.filter_sensitive_data('<SMSTOOLS_CLIENT_SECRET>') { ENV['SMSTOOLS_CLIENT_SECRET'] }

  # Allow localhost connections for system tests
  config.ignore_localhost = true
end

# Allow WebMock to work without VCR cassettes
WebMock.disable_net_connect!(allow_localhost: true)
