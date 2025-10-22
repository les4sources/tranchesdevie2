require 'apartment/elevators/subdomain'

Apartment.configure do |config|
  # Models that should be global (not tenant-scoped)
  config.excluded_models = %w[Tenant StripeEvent]

  # Function to get list of all tenant subdomains
  # Wrapped in begin/rescue to avoid errors during initial setup
  config.tenant_names = lambda do
    begin
      Tenant.pluck(:subdomain) if ActiveRecord::Base.connection.table_exists?('tenants')
    rescue
      []
    end
  end

  # Use Postgres schemas for isolation
  config.use_schemas = true
end

# Add middleware to switch tenants based on subdomain
Rails.application.config.middleware.use Apartment::Elevators::Subdomain
