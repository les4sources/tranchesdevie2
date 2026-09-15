require 'rails_helper'

# Parcours de DEMANDE d'une Pizza party privée (#pizza-parties).
#
# La demande ne paie rien, n'occupe aucun créneau et ne crée ni PartyEvent ni
# Order : ces trois faits sont le cœur du nouveau process et chacun a sa spec.
RSpec.describe "Demande de Pizza party privée", type: :request do
  let(:phone) { "+32470111222" }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  # Premier mardi ou vendredi au-delà du préavis : une date en dur casserait la
  # spec deux jours par semaine.
  let(:valid_date) do
    (PartyRequest::MINIMUM_NOTICE_DAYS..(PartyRequest::MINIMUM_NOTICE_DAYS + 14))
      .map { |n| Date.current + n }
      .find { |date| PartyEvent::PRIVATE_WDAYS.include?(date.wday) }
  end

  # L'adapter du projet est Solid Queue : en test, un `deliver_later` reste en
  # base et rien n'est observable. On bascule sur l'adapter `:test` (même patron
  # que party_team_notification_spec).
  around do |example|
    original_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original_adapter
  end

  def verify_phone!
    # Les endpoints OTP vivent dans le checkout et portent ses gardes de panier :
    # on les neutralise, la demande de party n'a pas de panier par construction.
    allow_any_instance_of(CheckoutController).to receive(:ensure_cart_not_empty)
    allow_any_instance_of(CheckoutController).to receive(:ensure_bake_day_set)
    allow(OtpService).to receive(:send_otp).and_return({ success: true })
    allow(OtpService).to receive(:verify_otp).and_return({ success: true })
    post '/checkout/verify_phone', params: { phone_e164: phone }
    post '/checkout/verify_otp', params: { code: '123456', first_name: 'Camille' }.to_json,
         headers: { 'CONTENT_TYPE' => 'application/json' }
  end

  def submit(overrides = {})
    post party_requests_path, params: {
      party_slot_choice: "#{valid_date.iso8601}|soir",
      persons: 8,
      customer_note: "Anniversaire de Jules, on arrive vers 18h30.",
      first_name: "Camille",
      last_name: "Dupont",
      email: "camille@example.com"
    }.merge(overrides)
  end

  describe "GET /pizza-party-privee/demande" do
    it "affiche le formulaire de demande" do
      get new_party_request_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Envoyer ma demande")
    end

    it "n'offre aucune date à moins de 10 jours (préavis)" do
      get new_party_request_path

      too_soon = (1...PartyRequest::MINIMUM_NOTICE_DAYS)
                   .map { |n| Date.current + n }
                   .select { |date| PartyEvent::PRIVATE_WDAYS.include?(date.wday) }

      too_soon.each do |date|
        expect(response.body).not_to include("data-date=\"#{date.iso8601}\"")
      end
    end
  end

  describe "POST /pizza-party-privee/demande" do
    before { verify_phone! }

    it "crée la demande sans PartyEvent ni Order" do
      expect { submit }.to change(PartyRequest, :count).by(1)
        .and change(PartyEvent, :count).by(0)
        .and change(Order, :count).by(0)

      party_request = PartyRequest.last
      expect(party_request).to be_state_pending
      expect(party_request.held_on).to eq(valid_date)
      expect(response).to redirect_to(party_request_sent_path(token: party_request.public_token))
    end

    it "sans Stripe : aucun PaymentIntent n'est créé" do
      expect(Stripe::PaymentIntent).not_to receive(:create)
      submit
    end

    it "fige les prix unitaires du jour de la demande" do
      submit
      items = PartyRequest.last.party_request_items
      expect(items.map(&:unit_price_cents)).to contain_exactly(1200, 4000)

      party_variant.update!(price_cents: 1500)
      expect(PartyRequest.last.party_request_items.map(&:unit_price_cents)).to contain_exactly(1200, 4000)
    end

    it "envoie l'accusé de réception au client et la notification à l'équipe" do
      expect { submit }.to have_enqueued_mail(PartyRequestMailer, :received)
        .and have_enqueued_mail(PartyRequestMailer, :new_request)
    end

    it "rend les deux e-mails sans erreur et les journalise" do
      perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) { submit }

      kinds = EmailMessage.where(party_request_id: PartyRequest.last.id).pluck(:kind)
      expect(kinds).to include("party_request_received", "party_request_team")
    end

    it "refuse une date à moins de 10 jours" do
      too_soon = (1...PartyRequest::MINIMUM_NOTICE_DAYS)
                   .map { |n| Date.current + n }
                   .find { |date| PartyEvent::PRIVATE_WDAYS.include?(date.wday) }
      skip "aucun jour de party sous le préavis cette semaine" if too_soon.nil?

      expect { submit(party_slot_choice: "#{too_soon.iso8601}|soir") }.not_to change(PartyRequest, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuse une demande sans e-mail" do
      expect { submit(email: "") }.not_to change(PartyRequest, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("adresse e-mail")
    end

    it "refuse un e-mail déjà rattaché à un autre client, avec un message explicite" do
      create(:customer, email: "camille@example.com")

      expect { submit }.not_to change(PartyRequest, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("déjà utilisée")
    end

    it "refuse un commentaire vide" do
      expect { submit(customer_note: "  ") }.not_to change(PartyRequest, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuse un commentaire trop long" do
      expect { submit(customer_note: "a" * (Order::CUSTOMER_NOTE_MAX_LENGTH + 1)) }
        .not_to change(PartyRequest, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST sans vérification OTP" do
    it "refuse la demande" do
      expect { submit }.not_to change(PartyRequest, :count)
      expect(response).to redirect_to(new_party_request_path)
    end
  end

  describe "suivi et annulation" do
    let(:party_request) { create(:party_request) }

    it "affiche l'état de la demande sans connexion" do
      get party_request_path(token: party_request.public_token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("En attente de réponse")
    end

    it "permet d'annuler tant que la demande est en attente" do
      delete cancel_party_request_path(token: party_request.public_token)
      expect(party_request.reload).to be_state_cancelled
    end

    it "refuse d'annuler une demande déjà traitée" do
      refused = create(:party_request, :refused)
      delete cancel_party_request_path(token: refused.public_token)
      expect(refused.reload).to be_state_refused
    end
  end
end
