require 'rails_helper'

# Notification interne « nouvelle Pizza party privée » (#168), vue depuis les
# deux tunnels réels : paiement en ligne (Stripe) et commande cash.
RSpec.describe 'Notification équipe — Pizza party privée', type: :request do
  let!(:default_pickup) { create(:pickup_location, :default) }

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

  let(:slot_choice) { "#{(Date.current + 8).iso8601}|soir" }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })
  end

  # L'adapter du projet est Solid Queue : en test, un `deliver_later` reste en
  # base et l'e-mail n'est jamais rendu. On bascule sur l'adapter `:test` pour
  # pouvoir vider la file d'envoi à la main (même patron que webhooks_spec).
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  # Ne joue QUE les jobs d'envoi d'e-mail : FetchStripeFeeJob, lui, appellerait
  # l'API Stripe pour de vrai.
  def deliver_pending_emails(&block)
    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob, &block)
  end

  def sign_in(customer)
    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
  end

  def notification_count(order)
    EmailMessage.where(order_id: order.id, kind: :party_team_notification).count
  end

  describe 'paiement en ligne (Stripe)' do
    let(:customer) { create(:customer, first_name: 'Léa', email: 'lea@example.com') }

    before do
      sign_in(customer)
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'Anniversaire de Léa, 4 adultes.', qty: 4 }
      stub_stripe_payment_intent_create(amount: (500 * 4) + 4000)
      post '/checkout/create_payment_intent',
           params: { first_name: 'Léa' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json' }
    end

    let(:order) { Order.order(:created_at).last }

    def deliver_webhook(payment_intent_id)
      pi = double('Stripe::PaymentIntent', id: payment_intent_id, metadata: {})
      event = double('Stripe::Event', id: "evt_#{SecureRandom.hex(6)}",
                                      type: 'payment_intent.succeeded',
                                      data: double('event_data', object: pi))
      allow(Stripe::Webhook).to receive(:construct_event).and_return(event)
      post '/webhooks/stripe', params: '{}', headers: { 'HTTP_STRIPE_SIGNATURE' => 't=1,v1=sig' }
    end

    it "journalise un EmailMessage de notification d'équipe une fois la commande payée" do
      expect(order.private_party?).to be true

      deliver_pending_emails { deliver_webhook(order.payment_intent_id) }

      expect(notification_count(order)).to eq(1)
      logged = EmailMessage.where(order_id: order.id, kind: :party_team_notification).first
      expect(logged.to_email).to include('boulangerie@les4sources.be', 'sejours@les4sources.be')
      expect(logged.customer_id).to be_nil
    end

    it "n'envoie pas un second e-mail si le webhook est rejoué" do
      deliver_pending_emails do
        deliver_webhook(order.payment_intent_id)
        deliver_webhook(order.payment_intent_id)
      end

      expect(notification_count(order)).to eq(1)
    end
  end

  describe 'commande cash' do
    let(:customer) do
      create(:customer, first_name: 'Yann', email: 'yann@example.com', cash_payment_allowed: true)
    end

    it "journalise un EmailMessage de notification d'équipe" do
      sign_in(customer)
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'Soirée d\'équipe, 7 personnes.', qty: 7 }

      deliver_pending_emails do
        post '/checkout/create_cash_order',
             params: { first_name: 'Yann' }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      expect(response).to have_http_status(:ok)
      order = Order.order(:created_at).last
      expect(order.private_party?).to be true
      expect(notification_count(order)).to eq(1)
    end
  end

  describe 'ce qui ne doit PAS déclencher de notification' do
    let(:customer) { create(:customer, first_name: 'Zoé', email: 'zoe@example.com', cash_payment_allowed: true) }
    let!(:bake_day) { create(:bake_day, :can_order) }
    let!(:bread_product) { create(:product, :bread, channel: 'store') }
    let!(:bread_variant) { create(:product_variant, product: bread_product, price_cents: 450, channel: 'store') }

    it "une commande de pain ordinaire n'en produit aucune" do
      sign_in(customer)
      post cart_add_path, params: { product_variant_id: bread_variant.id, bake_day_id: bake_day.id, qty: 2 }

      deliver_pending_emails do
        post '/checkout/create_cash_order',
             params: { first_name: 'Zoé', bake_day_id: bake_day.id }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      # Le test ne doit pas passer parce que rien n'a été commandé.
      order = Order.order(:created_at).last
      expect(order).to be_present
      expect(order.private_party?).to be false
      expect(EmailMessage.where(kind: :party_team_notification).count).to eq(0)
    end

    it "une inscription à une party PUBLIQUE n'en produit aucune" do
      public_product = create(:product, :pizza_party_public, channel: 'store')
      adulte = create(:product_variant, product: public_product, name: 'adulte', price_cents: 1_000, channel: 'store')
      event = create(:party_event, :public_party)

      sign_in(customer)
      post cart_add_path, params: { product_variant_id: adulte.id, public_party_event_id: event.id, qty: 2 }

      deliver_pending_emails do
        post '/checkout/create_cash_order',
             params: { first_name: 'Zoé' }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      order = Order.order(:created_at).last
      expect(order).to be_present
      expect(order.party_event).to eq(event)
      expect(order.private_party?).to be false
      expect(EmailMessage.where(kind: :party_team_notification).count).to eq(0)
    end
  end
end
