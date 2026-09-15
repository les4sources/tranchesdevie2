require 'rails_helper'

# Décision de la boulangerie sur une demande de Pizza party (#pizza-parties).
#
# La spec centrale du lot : **un GET ne décide jamais**. Gmail, Outlook et les
# scanners de sécurité préchargent les liens reçus par e-mail ; un lien
# « valider » qui agirait au chargement validerait des parties tout seul.
RSpec.describe "Admin — décision sur une demande de Pizza party", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  # Numéros et e-mails explicites : la base de test est partagée entre agents,
  # les séquences de factory finissent par se télescoper.
  let(:customer) { create(:customer, phone_e164: "+32470100200", email: "demande@example.com") }
  let(:party_request) { create(:party_request, customer: customer) }
  let(:token) { party_request.signed_id(purpose: :party_decision, expires_in: 30.days) }

  around do |example|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = adapter
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  describe "GET de la page de décision" do
    it "affiche un bouton sans rien décider — même rejoué trois fois" do
      3.times { get admin_party_decision_path(token: token, decision: "accept") }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Valider cette demande")
      expect(party_request.reload).to be_state_pending
      expect(party_request.order).to be_nil
      expect(PartyEvent.count).to eq(0)
    end

    it "affiche le formulaire de refus quand le lien porte la décision « refuse »" do
      get admin_party_decision_path(token: token, decision: "refuse")

      expect(response.body).to include("Motif du refus")
      expect(party_request.reload).to be_state_pending
    end

    it "rend une page d'erreur explicite sur un jeton altéré, sans 500" do
      get admin_party_decision_path(token: "#{token}xyz", decision: "accept")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Lien de décision invalide")
    end

    it "rend la même page sur un jeton expiré" do
      expired = party_request.signed_id(purpose: :party_decision, expires_in: 1.second)
      travel 2.seconds do
        get admin_party_decision_path(token: expired, decision: "accept")
        expect(response).to have_http_status(:not_found)
      end
    end

    it "refuse un jeton signé pour un autre usage" do
      other_purpose = party_request.signed_id(purpose: :email_unsubscribe)

      get admin_party_decision_path(token: other_purpose, decision: "accept")
      expect(response).to have_http_status(:not_found)
    end

    it "annonce « déjà traitée par … » sur une demande déjà décidée" do
      party_request.update!(state: :refused, decision_reason: "Four pris", decided_by: "Romane", decided_at: Time.current)

      get admin_party_decision_path(token: token, decision: "accept")

      expect(response.body).to include("déjà été traitée par Romane")
    end
  end

  describe "POST de validation" do
    it "crée la réservation, prévient le client et trace le décideur" do
      expect {
        post accept_admin_party_request_path(party_request), params: { decided_by: "Romane" }
      }.to change(Order, :count).by(1).and change(PartyEvent, :count).by(1)

      party_request.reload
      expect(party_request).to be_state_accepted
      expect(party_request.decided_by).to eq("Romane")
      expect(party_request.order).to be_awaiting_payment
    end

    it "est idempotent : la seconde validation ne crée rien et dit qui a tranché" do
      post accept_admin_party_request_path(party_request), params: { decided_by: "Romane" }

      expect {
        post accept_admin_party_request_path(party_request), params: { decided_by: "Thomas" }
      }.not_to change(Order, :count)

      follow_redirect!
      expect(response.body).to include("déjà été traitée par Romane").or include("déjà traitée")
      expect(party_request.reload.decided_by).to eq("Romane")
    end

    it "échoue proprement quand une party publique occupe déjà la soirée" do
      create(:party_event, :public_party, held_on: party_request.held_on)

      expect {
        post accept_admin_party_request_path(party_request), params: { decided_by: "Romane" }
      }.not_to change(Order, :count)

      expect(party_request.reload).to be_state_pending
    end
  end

  describe "POST de refus" do
    it "exige un motif" do
      post refuse_admin_party_request_path(party_request), params: { reason: "  " }

      expect(party_request.reload).to be_state_pending
      follow_redirect!
      expect(response.body).to include("raison du refus")
    end

    it "refuse avec le motif, qui part au client" do
      expect {
        post refuse_admin_party_request_path(party_request),
             params: { reason: "Le four est déjà pris ce soir-là.", decided_by: "Claire" }
      }.to have_enqueued_mail(PartyRequestMailer, :refused)

      party_request.reload
      expect(party_request).to be_state_refused
      expect(party_request.decision_reason).to eq("Le four est déjà pris ce soir-là.")
      expect(party_request.decided_by).to eq("Claire")
    end
  end

  describe "POST de retrait d'une validation" do
    it "annule la réservation non payée, rend le créneau et prévient le client" do
      post accept_admin_party_request_path(party_request), params: { decided_by: "Romane" }
      order = party_request.reload.order

      expect {
        post retract_admin_party_request_path(party_request), params: { reason: "Panne de four." }
      }.to have_enqueued_mail(PartyRequestMailer, :retracted)

      expect(order.reload).to be_cancelled
      expect(order.party_event.reload.deleted_at).to be_present
    end

    it "refuse de retirer une réservation déjà payée" do
      post accept_admin_party_request_path(party_request), params: { decided_by: "Romane" }
      order = party_request.reload.order
      order.update!(status: :paid)

      post retract_admin_party_request_path(party_request), params: { reason: "Trop tard." }

      expect(order.reload).to be_paid
    end
  end

  describe "correction du nombre par la boulangerie" do
    before do
      post accept_admin_party_request_path(party_request), params: { decided_by: "Romane" }
    end

    it "recalcule le montant aux tarifs figés et reprévient le client" do
      order = party_request.reload.order

      expect {
        patch update_headcount_admin_party_request_path(party_request), params: { persons: 15 }
      }.to have_enqueued_mail(PartyRequestMailer, :payment_prompt)

      order.reload
      expect(order.party_paton_count).to eq(15)
      expect(order.total_cents).to eq(15 * 1200 + 4000)
    end

    it "refuse un nombre inférieur à 1" do
      order = party_request.reload.order

      patch update_headcount_admin_party_request_path(party_request), params: { persons: 0 }

      expect(order.reload.party_paton_count).to eq(1)
    end

    it "refuse de corriger une réservation déjà payée" do
      order = party_request.reload.order
      order.update!(status: :paid)

      patch update_headcount_admin_party_request_path(party_request), params: { persons: 15 }

      expect(order.reload.party_paton_count).to eq(1)
    end
  end

  describe "la file des demandes" do
    it "liste les demandes en attente et les réservations non payées" do
      pending_request = party_request
      accepted = create(:party_request,
                        customer: create(:customer, phone_e164: "+32470100201", email: "deuxieme@example.com"))
      post accept_admin_party_request_path(accepted), params: { decided_by: "Romane" }

      get admin_party_requests_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("À traiter")
      expect(response.body).to include("Validées, paiement attendu")
      expect(response.body).to include(pending_request.customer.email)
      expect(response.body).to include(accepted.customer.email)
    end

    it "signale dans la file les demandes qu'une party publique rend invalidables" do
      create(:party_event, :public_party, held_on: party_request.held_on)

      get admin_party_requests_path

      expect(response.body).to include("Conflit : party publique ce soir-là")
    end

    it "affiche le compteur de demandes en attente dans la navigation" do
      party_request

      get admin_party_requests_path

      # Le compteur se lit en base : la base de test est partagée entre agents,
      # une valeur en dur casserait la spec dès qu'une ligne traîne.
      expected = PartyRequest.state_pending.count
      expect(expected).to be >= 1
      expect(response.body).to match(/Demandes party.{0,400}rounded-full.{0,200}>#{expected}</m)
    end
  end
end
