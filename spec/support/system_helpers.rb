# Helpers partagés pour les system specs du storefront (#126).
#
# Ils posent le harness dont dépendent les parcours navigateur : stub OTP,
# mock Stripe (serveur via les helpers de stripe_helper.rb + client via le shim
# window.Stripe injecté par layouts/_stripe_test_stub en env test), et
# authentification d'un client via le vrai flux OTP de /connexion.
module SystemHelpers
  # Neutralise l'envoi/vérification OTP (SMS + e-mail) pour les deux points
  # d'entrée : /connexion (send_code/verify_code) et le checkout (send_otp/verify_otp).
  # Aucun SMS ni e-mail réel n'est émis.
  def stub_customer_otp(code: "123456")
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code) do |args|
      { success: args[:code].to_s == code }
    end
    allow(OtpService).to receive(:send_otp).and_return({ success: true })
    allow(OtpService).to receive(:verify_otp) do |_phone, entered|
      { success: entered.to_s == code }
    end
  end

  # Stub Stripe côté serveur, en RÉUTILISANT les helpers de spec/support/stripe_helper.rb
  # (pas de duplication). `create` réserve un PaymentIntent modifiable ; `retrieve`
  # (appelé par la page success) le renvoie `processing` pour ne pas déclencher la
  # finalisation d'encaissement (hors périmètre de ce harness — couverte ailleurs).
  # Retourne l'id du PaymentIntent stubbé.
  def stub_stripe_checkout(total_cents:)
    intent = stub_stripe_payment_intent_create(amount: total_cents)
    stub_stripe_payment_intent_retrieve(id: intent.id, status: "processing", amount: total_cents)
    intent.id
  end

  # Authentifie un client via le VRAI parcours OTP de /connexion (UI navigateur,
  # OtpService stubé). Réutilisable par tous les parcours. Suppose que le client
  # existe déjà (identifiant reconnu → connexion directe).
  def sign_in_customer(customer, code: "123456")
    stub_customer_otp(code: code)
    visit customer_login_path
    fill_in "identifier", with: customer.phone_e164
    find("#send-otp-btn").click
    find("#otp-input-section:not(.hidden)", wait: 5)
    fill_in "otp_code", with: code
    find("#verify-otp-btn").click
    # sign_in redirige hors de /connexion : on attend d'avoir quitté la page de login.
    expect(page).to have_no_current_path(customer_login_path, wait: 5)
  end
end

RSpec.configure do |config|
  config.include SystemHelpers, type: :system
end
