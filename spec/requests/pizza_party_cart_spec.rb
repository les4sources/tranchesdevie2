require 'rails_helper'

# Panier + forfait Pizza party (#68) : le forfait est une ligne de panier
# auto-synchronisée, comptée une seule fois, incluse dans le total payé.
RSpec.describe 'Pizza party — panier & forfait', type: :request do
  let!(:party_product) do
    create(:product, :pizza_party, channel: 'store', name: 'Pizza party privée – Nombre de personnes')
  end
  let!(:party_variant) do
    create(:product_variant, product: party_product, name: 'une boule', price_cents: 500, channel: 'store')
  end

  let!(:forfait_product) { create(:product, :pizza_party_forfait, name: 'Forfait Pizza party privée') }
  let!(:forfait_variant) do
    create(:product_variant, product: forfait_product, name: 'forfait', price_cents: 4000, channel: 'store')
  end

  def forfait_lines(cart)
    (cart || []).select { |item| item['product_variant_id'] == forfait_variant.id.to_s }
  end

  describe 'POST /cart/add avec une variante de produit party' do
    it 'injecte automatiquement la ligne forfait' do
      post cart_add_path, params: { product_variant_id: party_variant.id, qty: 4 }

      cart = session[:cart]
      expect(forfait_lines(cart).size).to eq(1)
      expect(forfait_lines(cart).first['qty']).to eq(1)
      expect(forfait_lines(cart).first['price_cents']).to eq(4000)
    end

    it 'porte un sous-total = 500 × N + 4000 (forfait compté une fois)' do
      n = 4
      post cart_add_path, params: { product_variant_id: party_variant.id, qty: n }

      subtotal = session[:cart].sum { |item| item['qty'].to_i * item['price_cents'].to_i }
      expect(subtotal).to eq((500 * n) + 4000)
    end

    it 'ne double pas le forfait quand on ajoute encore des boules' do
      post cart_add_path, params: { product_variant_id: party_variant.id, qty: 2 }
      post cart_add_path, params: { product_variant_id: party_variant.id, qty: 3 }

      cart = session[:cart]
      expect(forfait_lines(cart).size).to eq(1)
      party_line = cart.find { |item| item['product_variant_id'] == party_variant.id.to_s }
      expect(party_line['qty']).to eq(5)
    end
  end

  describe 'DELETE /cart/remove du produit party' do
    it 'retire aussi le forfait' do
      post cart_add_path, params: { product_variant_id: party_variant.id, qty: 2 }
      expect(forfait_lines(session[:cart]).size).to eq(1)

      delete cart_remove_path(party_variant.id.to_s)
      expect(forfait_lines(session[:cart])).to be_empty
    end
  end

  describe 'le montant payé en ligne inclut le forfait' do
    let(:bake_day) { create(:bake_day, :can_order) }
    let(:customer) { create(:customer, first_name: 'Léa') }

    before do
      allow(OrderNotificationService).to receive(:send_confirmation)
      allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
      allow(OtpService).to receive(:verify_code).and_return({ success: true })
      post '/connexion', params: { identifier: customer.phone_e164 }
      post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }

      post cart_add_path, params: { product_variant_id: party_variant.id, bake_day_id: bake_day.id, qty: 4 }
      stub_stripe_payment_intent_create(amount: (500 * 4) + 4000)
    end

    it 'crée une commande dont le total = 500 × N + 4000' do
      post '/checkout/create_payment_intent',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      order = Order.order(:created_at).last
      expect(order.total_cents).to eq((500 * 4) + 4000)
    end

    it 'compte le forfait une seule fois parmi les items de commande' do
      post '/checkout/create_payment_intent',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }

      order = Order.order(:created_at).last
      forfait_items = order.order_items.select { |oi| oi.product_variant_id == forfait_variant.id }
      expect(forfait_items.size).to eq(1)
      expect(forfait_items.first.qty).to eq(1)
      expect(forfait_items.first.unit_price_cents).to eq(4000)
    end
  end
end
