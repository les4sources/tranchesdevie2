require 'rails_helper'

# Session-based cart (no DB cart model). Covers ISC-5/6/7/8.
RSpec.describe 'Cart', type: :request do
  let!(:product) { create(:product, category: :breads, channel: 'store') }
  let!(:variant) { create(:product_variant, product: product, channel: 'store') }

  describe 'POST /cart/add (ISC-5)' do
    it 'adds a variant to the session cart' do
      post cart_add_path, params: { product_variant_id: variant.id, qty: 2 }
      expect(session[:cart].size).to eq(1)
      item = session[:cart].first
      expect(item['product_variant_id']).to eq(variant.id.to_s)
      expect(item['qty']).to eq(2)
    end

    it 'increments the quantity when the variant is already in the cart' do
      post cart_add_path, params: { product_variant_id: variant.id, qty: 1 }
      post cart_add_path, params: { product_variant_id: variant.id, qty: 2 }
      expect(session[:cart].size).to eq(1)
      expect(session[:cart].first['qty']).to eq(3)
    end

    it 'refuses an inactive variant' do
      inactive = create(:product_variant, :inactive, product: product)
      post cart_add_path, params: { product_variant_id: inactive.id }
      expect(session[:cart]).to be_blank
    end
  end

  describe 'PATCH /cart/update (ISC-6)' do
    it 'changes the quantity of an existing line' do
      post cart_add_path, params: { product_variant_id: variant.id, qty: 1 }
      patch cart_update_path, params: { id: variant.id.to_s, qty: 5 }
      expect(session[:cart].first['qty']).to eq(5)
    end
  end

  describe 'PATCH /cart/update_bake_day (ISC-7)' do
    let!(:bake_day) { create(:bake_day, :can_order) }

    it 'selects an orderable, non-full bake day' do
      patch cart_update_bake_day_path, params: { bake_day_id: bake_day.id }, as: :json
      expect(session[:bake_day_id]).to eq(bake_day.id)
    end
  end

  describe 'DELETE /cart/remove/:id (ISC-8)' do
    it 'removes the line from the cart' do
      post cart_add_path, params: { product_variant_id: variant.id, qty: 1 }
      delete cart_remove_path(variant.id.to_s)
      expect(session[:cart]).to be_empty
    end
  end
end
