require 'rails_helper'

# Admin panel: auth gate + order write actions + section loads.
# Covers ISC-46, 47, 48, 49, 50, 51, 52, 54.
RSpec.describe 'Admin', type: :request do
  around do |ex|
    original = ENV['ADMIN_PASSWORD']
    ENV['ADMIN_PASSWORD'] = 'test-admin-pw'
    ex.run
    ENV['ADMIN_PASSWORD'] = original
  end

  def login_admin
    post admin_login_path, params: { password: 'test-admin-pw' }
  end

  describe 'authentication (ISC-46, ISC-54)' do
    it 'redirects an unauthenticated request to the login page (never 200)' do
      get admin_orders_path
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(admin_login_path)
    end

    it 'grants access after login with the correct password' do
      login_admin
      get admin_orders_path
      expect(response).to have_http_status(:ok)
    end

    it 'rejects a wrong password' do
      post admin_login_path, params: { password: 'nope' }
      get admin_orders_path
      expect(response).to redirect_to(admin_login_path)
    end
  end

  context 'when authenticated' do
    before { login_admin }

    it 'lists orders (ISC-47)' do
      create(:order, :with_items)
      get admin_orders_path
      expect(response).to have_http_status(:ok)
    end

    it 'transitions an order along a valid path via update_status (ISC-48)' do
      order = create(:order, :paid)
      patch update_status_admin_order_path(order), params: { status: 'ready' }
      expect(order.reload.status).to eq('ready')
    end

    it 'refuses an invalid status transition (ISC-48)' do
      order = create(:order, :paid)
      patch update_status_admin_order_path(order), params: { status: 'picked_up' }
      expect(order.reload.status).to eq('paid')
    end

    it 'delegates a refund to RefundService (ISC-49)' do
      order = create(:order, :paid)
      service = instance_double(RefundService, call: true, errors: [])
      expect(RefundService).to receive(:new).with(order).and_return(service)
      post refund_admin_order_path(order)
      expect(response).to redirect_to(admin_order_path(order))
    end

    it 'loads the products, bake-days and settings sections (ISC-50/51/52)' do
      aggregate_failures do
        get admin_products_path
        expect(response).to have_http_status(:ok)
        get new_admin_product_path
        expect(response).to have_http_status(:ok)
        get admin_bake_days_path
        expect(response).to have_http_status(:ok)
        get new_admin_bake_day_path
        expect(response).to have_http_status(:ok)
        get admin_settings_path
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
