class CreateTenants < ActiveRecord::Migration[8.0]
  def change
    create_table :tenants do |t|
      t.string :subdomain, null: false
      t.string :custom_domain
      t.string :name, null: false
      t.text :pickup_address
      t.string :timezone, default: 'Europe/Brussels'
      t.string :logo_url
      t.string :primary_color, limit: 7
      t.string :telerivet_project_id
      t.string :telerivet_phone_id
      t.string :telerivet_api_key
      t.string :stripe_account_id
      t.jsonb :production_defaults
      t.string :status, default: 'active'

      t.timestamps
    end

    add_index :tenants, :subdomain, unique: true
    add_index :tenants, :custom_domain, unique: true
  end
end
