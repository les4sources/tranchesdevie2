require 'rails_helper'

RSpec.describe "Customers::Calendar", type: :request do
  let(:customer) { create(:customer) }
  let!(:wallet) { create(:wallet, customer: customer, balance_cents: 5000) }

  # Create future bake days only (past bake days are not shown on the calendar)
  let!(:future_bake_day) { create(:bake_day, :can_order) }
  let!(:product_variant) { create(:product_variant, price_cents: 550) }

  before do
    # Authenticate customer by simulating OTP flow
    allow(OtpService).to receive(:send_otp).and_return({ success: true })
    allow(OtpService).to receive(:verify_otp).and_return({ success: true })

    # First call to send OTP
    post '/connexion', params: { phone_e164: customer.phone_e164 }
    # Second call to verify OTP
    post '/connexion', params: { phone_e164: customer.phone_e164, otp_code: '123456' }
  end

  describe "GET /calendrier" do
    it "returns success for authenticated customer" do
      get '/calendrier'
      expect(response).to have_http_status(:success)
    end

    it "displays the calendar page with bake days" do
      get '/calendrier'
      expect(response.body).to include('calendrier')
    end

    it "shows the wallet balance" do
      get '/calendrier'
      # The balance in euros should be displayed (5000 cents = 50€)
      expect(response.body).to include('50')
    end

    context "when not authenticated" do
      before do
        delete '/deconnexion'
      end

      it "redirects to login" do
        get '/calendrier'
        expect(response).to redirect_to('/connexion')
      end
    end
  end

  describe "PATCH /calendrier/update_day" do
    let(:items) do
      [{ product_variant_id: product_variant.id, qty: 2 }]
    end

    context "creating a new planned order" do
      it "creates a planned order" do
        expect {
          patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: items }, as: :json
        }.to change(Order.planned, :count).by(1)
      end

      it "returns success" do
        patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: items }, as: :json
        expect(response).to have_http_status(:success)
      end

      it "returns the order details in JSON" do
        patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: items }, as: :json
        expect(response.content_type).to include('application/json')
        json = JSON.parse(response.body)
        expect(json['total_cents']).to eq(1100) # 2 * 550
      end
    end

    context "updating an existing planned order" do
      let!(:existing_order) do
        create(:order, :planned, customer: customer, bake_day: future_bake_day, source: :calendar, total_cents: 550)
      end

      it "updates the order items" do
        patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: items }, as: :json

        existing_order.reload
        expect(existing_order.total_cents).to eq(1100)  # 2 * 550
      end

      it "does not create a new order" do
        expect {
          patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: items }, as: :json
        }.not_to change(Order, :count)
      end
    end

    context "removing items (empty array)" do
      let!(:existing_order) do
        create(:order, :planned, customer: customer, bake_day: future_bake_day, source: :calendar)
      end

      it "deletes the planned order" do
        expect {
          patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: [] }, as: :json
        }.to change(Order.planned, :count).by(-1)
      end

      it "returns success" do
        patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: [] }, as: :json
        expect(response).to have_http_status(:success)
      end
    end

    context "when cut-off has passed" do
      # Use a specific date to avoid conflict with future_bake_day
      let(:cut_off_passed_bake_day) do
        create(:bake_day, baked_on: Date.current + 10.days, cut_off_at: 1.hour.ago)
      end

      it "returns an error" do
        patch '/calendrier/update_day', params: { bake_day_id: cut_off_passed_bake_day.id, items: items }, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns an error message in JSON" do
        patch '/calendrier/update_day', params: { bake_day_id: cut_off_passed_bake_day.id, items: items }, as: :json
        json = JSON.parse(response.body)
        expect(json['error']).to be_present
      end
    end

    context "when not authenticated" do
      before do
        delete '/deconnexion'
      end

      it "returns unauthorized" do
        patch '/calendrier/update_day', params: { bake_day_id: future_bake_day.id, items: items }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
