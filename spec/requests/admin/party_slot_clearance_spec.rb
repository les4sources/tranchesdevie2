require 'rails_helper'

# Bloquer une soirée déjà réservée (#pizza-parties).
#
# Ce n'est pas un geste de calendrier : c'est annuler la soirée de vrais
# groupes. L'app doit les NOMMER avant d'agir, et ne rien envoyer tant que le
# boulanger n'a pas confirmé.
RSpec.describe "Admin — blocage d'un créneau déjà réservé", type: :request do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  around do |example|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = adapter
    ENV["ADMIN_PASSWORD"] = original
  end

  before do
    post admin_login_path, params: { password: "test-admin-pw" }
    allow(Stripe::Refund).to receive(:create).and_return(double(status: "succeeded"))
    allow(Stripe::PaymentIntent).to receive(:cancel)
  end

  let(:customer) { create(:customer, first_name: "Fabienne", phone_e164: "+32470111000", email: "groupe@example.com") }
  let(:party_request) { create(:party_request, customer: customer) }
  let!(:order) { PartyDecisionService.new(party_request, decided_by: "Romane").accept }
  let(:held_on) { party_request.held_on }

  def block!(confirmed: false, reason: nil)
    params = { party_slot_block: { blocked_on: held_on.to_s, slot: "soir", reason: "Four en panne" } }
    params[:confirmed] = "1" if confirmed
    params[:cancellation_reason] = reason if reason
    post admin_party_slot_blocks_path, params: params
  end

  describe "premier envoi, sans confirmation" do
    it "montre les groupes concernés et n'annule rien" do
      block!

      # 422 : le statut que Turbo Drive exige pour réafficher une page après un
      # POST. En 200, l'écran de confirmation n'apparaissait pas du tout.
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Cette soirée est déjà réservée")
      expect(response.body).to include("Fabienne")
      expect(response.body).to include("Bloquer et annuler ces réservations")

      expect(PartySlotBlock.count).to eq(0)
      expect(order.reload).to be_awaiting_payment
      expect(order.party_event.reload.deleted_at).to be_nil
    end

    it "signale les demandes en attente sans les décider" do
      pending_request = create(:party_request,
                               customer: create(:customer, phone_e164: "+32470111001", email: "attente@example.com"),
                               held_on: held_on)

      block!

      expect(response.body).to include("en attente sur cette date")
      expect(pending_request.reload).to be_state_pending
    end
  end

  describe "après confirmation" do
    it "annule une réservation non payée, rend le créneau et prévient le client" do
      expect { block!(confirmed: true, reason: "Le four doit être réparé.") }
        .to have_enqueued_mail(PartyRequestMailer, :cancelled_by_bakery)

      expect(PartySlotBlock.count).to eq(1)
      expect(order.reload).to be_cancelled
      expect(order.cancelled_by).to eq("bakery")
      expect(order.party_event.reload.deleted_at).to be_present
    end

    it "rembourse une réservation payée et prévient l'équipe" do
      order.update!(status: :paid, payment_status: :paid)
      create(:payment, order: order, status: :succeeded, stripe_payment_intent_id: "pi_block")

      expect { block!(confirmed: true) }
        .to have_enqueued_mail(PartyRequestMailer, :refunded)
        .and have_enqueued_mail(PartyRequestMailer, :team_cancellation)

      expect(Stripe::Refund).to have_received(:create)
      expect(order.reload).to be_cancelled
      expect(order.cancelled_by).to eq("bakery")
    end

    it "annonce le nombre de réservations annulées" do
      block!(confirmed: true)

      follow_redirect!
      expect(response.body).to include("1 réservation annulée")
    end
  end

  describe "sur une date libre" do
    it "bloque directement, sans écran de confirmation" do
      free_date = held_on + 7

      post admin_party_slot_blocks_path,
           params: { party_slot_block: { blocked_on: free_date.to_s, slot: "soir", reason: "Congés" } }

      expect(response).to redirect_to(admin_party_slot_blocks_path)
      expect(PartySlotBlock.find_by(blocked_on: free_date)).to be_present
    end
  end
end
