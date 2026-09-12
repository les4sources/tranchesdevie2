require 'rails_helper'

# Post-it « Pizza party » sur le calendrier de claudy (#259), vu depuis les
# tunnels réels : paiement en ligne (Stripe), commande cash, et les deux chemins
# de remboursement. Aucun appel réseau réel — WebMock stube claudy.
#
# Calqué sur spec/requests/party_team_notification_spec.rb : la note se pose au
# même moment que l'e-mail interne à l'équipe.
RSpec.describe 'Note calendrier claudy — Pizza party privée', type: :request do
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

  let(:api_url) { 'https://claudy.test' }
  let(:notes_url) { "#{api_url}/api/v1/notes" }

  # Mardi de la semaine suivante : toujours au-delà de la limite « veille 16 h ».
  let(:party_date) { Date.current.next_occurring(:tuesday) + 7 }
  let(:slot_choice) { "#{party_date.iso8601}|soir" }

  before do
    allow(OrderNotificationService).to receive(:send_confirmation)
    allow(OrderNotificationService).to receive(:send_party_team_notification)
    allow(OtpService).to receive(:send_code).and_return({ success: true, channel: :sms })
    allow(OtpService).to receive(:verify_code).and_return({ success: true })
    stub_request(:post, notes_url)
      .to_return(status: 201, body: { id: 501 }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    original_url = ENV['CLAUDY_API_URL']
    original_token = ENV['CLAUDY_API_TOKEN']
    ActiveJob::Base.queue_adapter = :test
    ENV['CLAUDY_API_URL'] = api_url
    ENV['CLAUDY_API_TOKEN'] = 'tok_claudy'
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
    ENV['CLAUDY_API_URL'] = original_url
    ENV['CLAUDY_API_TOKEN'] = original_token
  end

  # Ne joue QUE les jobs de synchro claudy : FetchStripeFeeJob appellerait Stripe
  # pour de vrai, et les mails partiraient inutilement.
  def perform_claudy_jobs(&block)
    perform_enqueued_jobs(only: SyncClaudyPartyNoteJob, &block)
  end

  def sign_in(customer)
    post '/connexion', params: { identifier: customer.phone_e164 }
    post '/connexion', params: { identifier: customer.phone_e164, otp_code: '123456' }
  end

  describe 'paiement en ligne (Stripe)' do
    let(:customer) { create(:customer, first_name: 'Léa', last_name: 'Martin', email: 'lea@example.com') }

    before do
      sign_in(customer)
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: 'Anniversaire de Léa.', qty: 4 }
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

    it "pose la note une fois la commande payée" do
      expect(order.private_party?).to be true

      perform_claudy_jobs { deliver_webhook(order.payment_intent_id) }

      expect(a_request(:post, notes_url).with { |req|
        body = JSON.parse(req.body)['note']
        body['color'] == 'orange' &&
          body['external_ref'] == "tranchesdevie-order-#{order.id}" &&
          body['body'] == "Pizza Party privée\nSoirée : Léa Martin - 4 personnes" &&
          body['date'] == party_date.iso8601
      }).to have_been_made.once
      expect(order.reload.claudy_note_id).to eq(501)
    end

    it "ne pose pas de seconde note si le webhook est rejoué" do
      perform_claudy_jobs do
        deliver_webhook(order.payment_intent_id)
        deliver_webhook(order.payment_intent_id)
      end

      expect(a_request(:post, notes_url)).to have_been_made.once
    end

    it "une commande restée pending n'enfile aucun job et ne pose aucune note" do
      expect(order.status).to eq('pending')

      expect(enqueued_jobs.select { |j| j['job_class'] == 'SyncClaudyPartyNoteJob' }).to be_empty
      expect(a_request(:post, notes_url)).not_to have_been_made
      expect(order.reload.claudy_note_id).to be_nil
    end

    # DoD : sans CLAUDY_API_TOKEN — l'état du poste de développement et de la CI —
    # le tunnel se déroule exactement comme avant, sans le moindre appel sortant.
    it "sans CLAUDY_API_TOKEN, le paiement aboutit sans aucun appel à claudy" do
      ENV.delete('CLAUDY_API_TOKEN')

      perform_claudy_jobs { deliver_webhook(order.payment_intent_id) }

      expect(order.reload.status).to eq('paid')
      expect(a_request(:any, /claudy\.test/)).not_to have_been_made
      expect(order.claudy_note_id).to be_nil
    end
  end

  describe 'commande cash' do
    let(:customer) do
      create(:customer, first_name: 'Yann', last_name: 'Dupont', email: 'yann@example.com', cash_payment_allowed: true)
    end

    it "pose la note" do
      sign_in(customer)
      post cart_add_path, params: { product_variant_id: party_variant.id, party_slot_choice: slot_choice, party_note: "Soirée d'équipe.", qty: 7 }

      perform_claudy_jobs do
        post '/checkout/create_cash_order',
             params: { first_name: 'Yann' }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      expect(response).to have_http_status(:ok)
      order = Order.order(:created_at).last
      expect(order.private_party?).to be true
      expect(a_request(:post, notes_url).with { |req|
        JSON.parse(req.body)['note']['body'] == "Pizza Party privée\nSoirée : Yann Dupont - 7 personnes"
      }).to have_been_made.once
      expect(order.reload.claudy_note_id).to eq(501)
    end
  end

  describe 'ce qui ne doit PAS poser de note' do
    let(:customer) { create(:customer, first_name: 'Zoé', email: 'zoe@example.com', cash_payment_allowed: true) }
    let!(:bake_day) { create(:bake_day, :can_order) }
    let!(:bread_product) { create(:product, :bread, channel: 'store') }
    let!(:bread_variant) { create(:product_variant, product: bread_product, price_cents: 450, channel: 'store') }

    it "une commande de fournée ordinaire" do
      sign_in(customer)
      post cart_add_path, params: { product_variant_id: bread_variant.id, bake_day_id: bake_day.id, qty: 2 }

      perform_claudy_jobs do
        post '/checkout/create_cash_order',
             params: { first_name: 'Zoé', bake_day_id: bake_day.id }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      order = Order.order(:created_at).last
      expect(order.private_party?).to be false
      expect(a_request(:post, notes_url)).not_to have_been_made
    end

    it "une inscription à une party PUBLIQUE" do
      public_product = create(:product, :pizza_party_public, channel: 'store')
      adulte = create(:product_variant, product: public_product, name: 'adulte', price_cents: 1_000, channel: 'store')
      event = create(:party_event, :public_party)

      sign_in(customer)
      post cart_add_path, params: { product_variant_id: adulte.id, public_party_event_id: event.id, qty: 2 }

      perform_claudy_jobs do
        post '/checkout/create_cash_order',
             params: { first_name: 'Zoé' }.to_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      order = Order.order(:created_at).last
      expect(order.party_event).to eq(event)
      expect(order.private_party?).to be false
      expect(a_request(:post, notes_url)).not_to have_been_made
    end
  end

  describe 'remboursement' do
    let(:customer) { create(:customer, first_name: 'Michael', last_name: 'Hulet') }
    let(:event) { create(:party_event, :private_party, held_on: party_date) }

    # Commande party privée PAYÉE, dont la note est déjà posée sur claudy.
    def paid_private_party_order(with_payment:)
      order = create(:order, customer: customer, bake_day: nil, party_event: event, source: :party,
                             status: :paid, total_cents: 6_000, claudy_note_id: 501)
      create(:order_item, order: order, product_variant: party_variant, qty: 4, unit_price_cents: 500)
      create(:payment, order: order, status: :succeeded) if with_payment
      order.reload
    end

    before { allow(SmsService).to receive(:send_refund) }

    it "chemin Stripe : supprime la note et remet claudy_note_id à nil" do
      order = paid_private_party_order(with_payment: true)
      delete_stub = stub_request(:delete, "#{notes_url}/501").to_return(status: 204)
      allow(Stripe::Refund).to receive(:create).and_return(double('refund', status: 'succeeded'))

      perform_claudy_jobs { expect(RefundService.new(order).call).to be true }

      expect(delete_stub).to have_been_requested
      expect(order.reload.claudy_note_id).to be_nil
    end

    it "chemin portefeuille : supprime la note et remet claudy_note_id à nil" do
      order = paid_private_party_order(with_payment: false)
      create(:wallet, customer: customer, balance_cents: 0)
      delete_stub = stub_request(:delete, "#{notes_url}/501").to_return(status: 204)

      perform_claudy_jobs { expect(RefundService.new(order).call).to be true }

      expect(delete_stub).to have_been_requested
      expect(order.reload.claudy_note_id).to be_nil
    end
  end
end
