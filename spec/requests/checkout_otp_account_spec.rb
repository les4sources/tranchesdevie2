require 'rails_helper'

# Régression du « compte fantôme » : avant, /checkout/verify_otp faisait
# Customer.find_or_create_by(phone) — qui échouait en silence (first_name
# obligatoire) → session « vérifiée » SANS aucun client en base, d'où des
# mangeurs absents de l'admin. Le client doit désormais être créé de façon fiable
# (avec le prénom du formulaire), et jamais de customer_id factice.
RSpec.describe "Checkout — création de compte à la validation OTP", type: :request do
  let(:phone) { "+32470555666" }

  before do
    # Isoler des gardes panier/jour (couvertes ailleurs).
    allow_any_instance_of(CheckoutController).to receive(:ensure_cart_not_empty)
    allow_any_instance_of(CheckoutController).to receive(:ensure_bake_day_set)

    allow(OtpService).to receive(:send_otp).and_return({ success: true })
    allow(OtpService).to receive(:verify_otp).and_return({ success: true })

    # Pose session[:phone_e164] (étape verify_phone), comme le ferait le tunnel.
    post '/checkout/verify_phone', params: { phone_e164: phone }
  end

  def verify_otp(body)
    post '/checkout/verify_otp', params: body.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }
  end

  context "nouveau numéro avec un prénom saisi" do
    it "crée un client persisté (présent dans les Mangeurs)" do
      expect {
        verify_otp(code: '123456', first_name: 'Camille', last_name: 'Dupont')
      }.to change(Customer, :count).by(1)

      expect(response).to have_http_status(:ok)
      customer = Customer.find_by(phone_e164: phone)
      expect(customer).to be_present
      expect(customer.first_name).to eq('Camille')
      expect(customer.last_name).to eq('Dupont')
    end
  end

  context "nouveau numéro SANS prénom" do
    it "ne crée pas de compte fantôme et ne lève pas d'erreur" do
      expect {
        verify_otp(code: '123456')
      }.not_to change(Customer, :count)

      expect(response).to have_http_status(:ok)
      expect(Customer.find_by(phone_e164: phone)).to be_nil
    end
  end

  context "numéro déjà connu" do
    it "réutilise le client existant sans le dupliquer" do
      existing = create(:customer, phone_e164: phone, first_name: 'Léa')

      expect {
        verify_otp(code: '123456', first_name: 'Ignoré')
      }.not_to change(Customer, :count)

      expect(response).to have_http_status(:ok)
      expect(Customer.where(phone_e164: phone).first).to eq(existing)
    end
  end
end
