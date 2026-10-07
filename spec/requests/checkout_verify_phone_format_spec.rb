require 'rails_helper'

# « Le bouton pour s'inscrire par SMS ne marche pas » : le tunnel n'acceptait
# qu'un numéro déjà au format « +32… ». La conversion d'un « 0470 12 34 56 »
# reposait entièrement sur le JS (libphonenumber via CDN, au blur du champ) ;
# s'il manquait, le nouveau client recevait « Format de téléphone invalide ».
RSpec.describe "Checkout — format du GSM à l'envoi du code", type: :request do
  before do
    allow_any_instance_of(CheckoutController).to receive(:ensure_cart_not_empty)
    allow_any_instance_of(CheckoutController).to receive(:ensure_bake_day_set)
    allow(OtpService).to receive(:send_otp).and_return({ success: true })
  end

  {
    "0470 12 34 56" => "+32470123456",
    "0470/12.34.56" => "+32470123456",
    "0032 470 12 34 56" => "+32470123456",
    "+32 0470 12 34 56" => "+32470123456",
    "+32470123456" => "+32470123456"
  }.each do |typed, expected|
    it "accepte « #{typed} » et l'envoie en #{expected}" do
      post '/checkout/verify_phone', params: { phone_e164: typed }

      expect(response).to have_http_status(:ok)
      expect(OtpService).to have_received(:send_otp).with(expected)
    end
  end

  it "refuse une saisie qui n'est pas un numéro" do
    post '/checkout/verify_phone', params: { phone_e164: "abc" }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to eq("Format de téléphone invalide")
    expect(OtpService).not_to have_received(:send_otp)
  end
end
