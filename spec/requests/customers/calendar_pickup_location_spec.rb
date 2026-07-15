require 'rails_helper'

# Point de retrait dans le calendrier (#148) : choisi date par date.
RSpec.describe 'Calendrier — point de retrait', type: :request do
  let!(:default_location) { create(:pickup_location, :default) }
  let!(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }

  let(:customer) { create(:customer) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let!(:variant) { create(:product_variant, price_cents: 700) }

  before do
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })

    bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
    bake_day.save!

    create(:wallet, customer: customer, balance_cents: 50_000)

    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
  end

  def update_day(params)
    patch '/calendrier/update_day', params: params.to_json,
          headers: { 'CONTENT_TYPE' => 'application/json' }
  end

  it 'persiste le point de retrait transmis' do
    update_day(
      bake_day_id: bake_day.id,
      items: [ { product_variant_id: variant.id, qty: 2 } ],
      pickup_location_id: anhee.id
    )

    expect(response).to have_http_status(:ok)
    expect(customer.orders.last.pickup_location).to eq(anhee)
  end

  it 'conserve le lieu quand une mise à jour ne touche que les articles' do
    update_day(
      bake_day_id: bake_day.id,
      items: [ { product_variant_id: variant.id, qty: 2 } ],
      pickup_location_id: anhee.id
    )

    update_day(
      bake_day_id: bake_day.id,
      items: [ { product_variant_id: variant.id, qty: 4 } ]
    )

    order = customer.orders.last
    expect(order.pickup_location).to eq(anhee)
    expect(order.order_items.sum(&:qty)).to eq(4)
  end

  it "rejette un lieu non ouvert sur la fournée" do
    closed = create(:pickup_location, name: "Marché de Dinant")

    update_day(
      bake_day_id: bake_day.id,
      items: [ { product_variant_id: variant.id, qty: 1 } ],
      pickup_location_id: closed.id
    )

    expect(response).to have_http_status(:unprocessable_entity)
    expect(customer.orders.count).to eq(0)
  end

  it "retombe sur le lieu par défaut si aucun lieu n'est transmis" do
    update_day(
      bake_day_id: bake_day.id,
      items: [ { product_variant_id: variant.id, qty: 1 } ]
    )

    expect(customer.orders.last.pickup_location).to eq(default_location)
  end

  describe 'affichage du calendrier' do
    it 'expose les lieux ouverts par fournée et le lieu pré-rempli' do
      # Le dernier lieu choisi par le client sert de pré-remplissage.
      create(:order, customer: customer, bake_day: bake_day, pickup_location: anhee)

      get '/calendrier'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-calendar-pickup-locations-value')
      expect(response.body).to include("data-calendar-preferred-pickup-location-value=\"#{anhee.id}\"")
    end
  end
end
