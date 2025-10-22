module TenantScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_current_tenant
  end

  private

  def set_current_tenant
    tenant = find_tenant_by_domain

    if tenant
      Apartment::Tenant.switch!(tenant.subdomain)
      Current.tenant = tenant
    else
      render plain: "Tenant not found", status: 404
    end
  end

  def find_tenant_by_domain
    # Try custom domain first
    tenant = Tenant.find_by(custom_domain: request.host)
    return tenant if tenant

    # Then try subdomain
    subdomain = request.subdomains.first
    Tenant.find_by(subdomain: subdomain) if subdomain.present?
  end
end
