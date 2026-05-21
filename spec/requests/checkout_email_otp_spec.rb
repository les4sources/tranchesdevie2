require 'rails_helper'

RSpec.describe "Checkout email OTP fallback", type: :request do
  # Isolate verify_phone from the cart/bake-day guards (covered elsewhere).
  before do
    allow_any_instance_of(CheckoutController).to receive(:ensure_cart_not_empty)
    allow_any_instance_of(CheckoutController).to receive(:ensure_bake_day_set)
  end

  let(:phone) { "+32470333444" }

  describe "POST /checkout/verify_phone with channel=email" do
    it "asks for an email when the phone is unregistered and none is provided" do
      post '/checkout/verify_phone', params: { phone_e164: phone, channel: 'email' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["need_email"]).to be true
    end

    it "sends the code to a typed email for an unregistered phone" do
      post '/checkout/verify_phone', params: { phone_e164: phone, channel: 'email', email: 'newcomer@example.com' }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to be true
      expect(ActionMailer::Base.deliveries.last.to).to eq([ 'newcomer@example.com' ])
    end

    it "sends to the on-file email for an existing customer, ignoring a typed address" do
      create(:customer, phone_e164: phone, email: 'onfile@example.com')
      post '/checkout/verify_phone', params: { phone_e164: phone, channel: 'email', email: 'attacker@example.com' }
      expect(JSON.parse(response.body)["success"]).to be true
      expect(ActionMailer::Base.deliveries.last.to).to eq([ 'onfile@example.com' ])
    end

    it "refuses an existing customer without an email on file" do
      create(:customer, phone_e164: phone, email: nil)
      post '/checkout/verify_phone', params: { phone_e164: phone, channel: 'email', email: 'typed@example.com' }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/contacte-nous/i)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
