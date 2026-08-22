require 'rails_helper'

RSpec.describe "Admin::Products variant cost prices (#90)", type: :request do
  let(:product) { create(:product) }
  let(:variant) { create(:product_variant, product: product) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ADMIN_PASSWORD').and_return('secret')
    post admin_login_path, params: { password: 'secret' }
  end

  describe "GET /admin/products/:id/variants/:variant_id/edit" do
    it "renders the cost price section" do
      get edit_variant_admin_product_path(product, variant)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Prix coûtant")
    end
  end

  describe "PATCH /admin/products/:id/variants/:variant_id" do
    it "accepts a cost price amount and an activation date" do
      patch variant_admin_product_path(product, variant), params: {
        product_variant: {
          name: variant.name,
          price_euros: "5.50",
          channel: "store",
          variant_cost_prices_attributes: {
            "0" => { amount_euros: "0.67", active_from: "2026-01-01" }
          }
        }
      }

      expect(response).to redirect_to(admin_product_path(product))
      cost_price = variant.reload.variant_cost_prices.last
      expect(cost_price).to be_present
      expect(cost_price.amount_cents).to eq(67)
      expect(cost_price.active_from).to eq(Date.new(2026, 1, 1))
    end

    it "ignores a blank cost price row" do
      expect do
        patch variant_admin_product_path(product, variant), params: {
          product_variant: {
            name: variant.name,
            price_euros: "5.50",
            channel: "store",
            variant_cost_prices_attributes: {
              "0" => { amount_euros: "", active_from: "" }
            }
          }
        }
      end.not_to change(VariantCostPrice, :count)
    end
  end
end
