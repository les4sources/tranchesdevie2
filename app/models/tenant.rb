class Tenant < ApplicationRecord
  validates :subdomain, presence: true, uniqueness: true
  validates :name, presence: true

  after_create :create_tenant_schema
  after_destroy :drop_tenant_schema

  private

  def create_tenant_schema
    Apartment::Tenant.create(subdomain)
  rescue Apartment::TenantExists
    # Schema already exists, that's okay
  end

  def drop_tenant_schema
    Apartment::Tenant.drop(subdomain)
  rescue Apartment::TenantNotFound
    # Schema already gone, that's okay
  end
end
