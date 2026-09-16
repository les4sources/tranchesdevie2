require 'rails_helper'

# Annulation et remboursement d'une Pizza party (#pizza-parties).
#
# Deux règles que le code ne respectait pas : sur ce parcours, le client est
# prévenu par E-MAIL (jamais par SMS), et l'équipe séjours doit apprendre la
# disparition d'un groupe, pas seulement son arrivée.
RSpec.describe "Annulation d’une Pizza party" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  around do |example|
    adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = adapter
  end

  let(:customer) { create(:customer, phone_e164: "+32470909090", email: "annule@example.com") }
  let(:party_request) { create(:party_request, customer: customer) }
  let(:order) { PartyDecisionService.new(party_request, decided_by: "Romane").accept }

  def pay!(order)
    order.update!(status: :paid, payment_status: :paid)
    create(:payment, order: order, status: :succeeded, stripe_payment_intent_id: "pi_paid")
    order
  end

  describe RefundService do
    before do
      allow(Stripe::Refund).to receive(:create).and_return(double(status: "succeeded"))
      allow(SmsService).to receive(:send_refund)
    end

    it "prévient le client par e-mail et JAMAIS par SMS" do
      paid = pay!(order)

      expect { RefundService.new(paid, cancelled_by: "customer").call }
        .to have_enqueued_mail(PartyRequestMailer, :refunded)

      expect(SmsService).not_to have_received(:send_refund)
    end

    it "prévient l'équipe séjours de la disparition du groupe" do
      paid = pay!(order)

      expect { RefundService.new(paid, cancelled_by: "bakery").call }
        .to have_enqueued_mail(PartyRequestMailer, :team_cancellation)
    end

    it "rend le créneau en supprimant l'événement" do
      paid = pay!(order)
      event = paid.party_event

      RefundService.new(paid, cancelled_by: "customer").call

      expect(event.reload.deleted_at).to be_present
      expect(PartyEvent.private_slot_available?(party_request.held_on, "soir")).to be true
    end

    it "garde le SMS pour une commande de pain" do
      bread_order = create(:order, :paid, customer: customer)
      create(:payment, order: bread_order, status: :succeeded, stripe_payment_intent_id: "pi_bread")

      RefundService.new(bread_order).call

      expect(SmsService).to have_received(:send_refund)
    end
  end

  describe "les états racontés au client" do
    include PartyRequestsHelper

    it "distingue l'annulation du client de celle de la boulangerie" do
      paid = pay!(order)
      paid.update!(status: :cancelled, payment_status: :refunded, cancelled_by: "customer")
      expect(party_request_state_label(party_request.reload, paid)).to eq("Réservation annulée et remboursée")
      expect(party_request_state_explanation(party_request, paid)).to match(/Tu as annulé/)

      paid.update!(cancelled_by: "bakery")
      expect(party_request_state_label(party_request, paid.reload))
        .to eq("Réservation annulée par la boulangerie et remboursée")
      expect(party_request_state_explanation(party_request, paid)).to match(/désolés/)
    end

    it "distingue une annulation avant paiement d'une expiration" do
      order.update!(status: :cancelled, cancelled_by: "customer")
      expect(party_request_state_label(party_request.reload, order)).to eq("Réservation annulée")

      order.update!(cancelled_by: nil)
      expect(party_request_state_label(party_request, order.reload)).to eq("Réservation expirée")
    end
  end

  describe "annulation en ligne par le client", type: :request do
    before { allow(Stripe::Refund).to receive(:create).and_return(double(status: "succeeded")) }

    it "rembourse une party payée tant que le cut-off n'est pas passé" do
      paid = pay!(order)

      delete cancel_party_request_path(token: party_request.public_token)

      expect(paid.reload).to be_cancelled
      expect(paid.payment.reload.status).to eq("refunded")
      expect(paid.cancelled_by).to eq("customer")
    end

    it "refuse après le cut-off et renvoie vers la boulangerie" do
      paid = pay!(order)

      travel_to(party_request.deadline_at + 1.hour) do
        delete cancel_party_request_path(token: party_request.public_token)
      end

      expect(paid.reload).to be_paid
      follow_redirect!
      expect(response.body).to include("Appelle-nous")
    end

    it "rend le créneau d'une réservation non payée sans rien rembourser" do
      order

      expect(Stripe::Refund).not_to receive(:create)
      delete cancel_party_request_path(token: party_request.public_token)

      expect(order.reload).to be_cancelled
      expect(order.party_event.reload.deleted_at).to be_present
    end
  end
end
