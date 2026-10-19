require "rails_helper"

# Encart « D'où viens-tu ? » (retour Michael 19/10/2026).
RSpec.describe "Customers::Account locality", type: :request do
  let(:customer) { create(:customer, locality: nil) }

  before do
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })
    post "/connexion", params: { identifier: customer.phone_e164 }
    post "/connexion", params: { identifier: customer.phone_e164, otp_code: "123456" }
  end

  it "affiche l'encart tant que le village est inconnu" do
    get customers_account_path

    expect(response.body).to include("D'où viens-tu ?")
  end

  it "enregistre le village et masque l'encart" do
    patch customers_account_locality_path, params: { locality: "godinne" }

    expect(customer.reload.locality).to eq("Godinne")
    follow_redirect!
    expect(response.body).not_to include("D'où viens-tu ?")
    expect(response.body).to include("Godinne")
  end

  it "ne redemande plus à qui préfère ne pas répondre" do
    patch customers_account_locality_path, params: { dismiss: 1 }

    expect(customer.reload.locality_prompt_dismissed_at).to be_present
    expect(customer.locality).to be_nil
    get customers_account_path
    expect(response.body).not_to include("D'où viens-tu ?")
  end

  it "refuse un village vide" do
    patch customers_account_locality_path, params: { locality: "  " }

    expect(customer.reload.locality).to be_nil
    expect(flash[:alert]).to be_present
  end

  it "permet de modifier le village depuis le profil" do
    patch customers_account_path, params: { customer: { first_name: customer.first_name, phone_e164: customer.phone_e164, locality: "Spontin" } }

    expect(customer.reload.locality).to eq("Spontin")
  end
end
