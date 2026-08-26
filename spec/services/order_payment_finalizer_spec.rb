require "rails_helper"

RSpec.describe OrderPaymentFinalizer do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let(:customer) { create(:customer, email: "client@example.com") }
  let(:party_product) { create(:product, :pizza_party) }
  let(:paton) { create(:product_variant, product: party_product, name: "pâton", price_cents: 1_000) }

  before { allow(OrderNotificationService).to receive(:send_confirmation) }

  def private_party_order
    PartyOrderCreationService.new(
      customer: customer,
      party_event: create(:party_event, :private_party, held_on: Date.new(2026, 9, 4)),
      cart_items: [ { "product_variant_id" => paton.id.to_s, "qty" => "6" } ]
    ).call
  end

  describe "notification d'équipe pour une party privée (#168)" do
    it "notifie l'équipe au premier enregistrement du paiement" do
      order = private_party_order

      expect(OrderNotificationService).to receive(:send_party_team_notification).with(order).once

      described_class.call(order: order, payment_intent_id: "pi_test_168")
    end

    it "ne notifie pas de nouveau quand le paiement est rejoué (webhook / page succès / job)" do
      order = private_party_order
      described_class.call(order: order, payment_intent_id: "pi_test_168")

      expect(OrderNotificationService).not_to receive(:send_party_team_notification)

      described_class.call(order: order, payment_intent_id: "pi_test_168")
      described_class.call(order: order, payment_intent_id: "pi_test_168")
    end

    it "laisse la commande payée et confirmée" do
      order = private_party_order
      allow(OrderNotificationService).to receive(:send_party_team_notification)

      described_class.call(order: order, payment_intent_id: "pi_test_168")

      expect(order.reload).to be_paid
      expect(order.paid_at).to be_present
    end
  end
end
