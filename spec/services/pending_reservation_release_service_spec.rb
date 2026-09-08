require 'rails_helper'

RSpec.describe PendingReservationReleaseService do
  include ActiveSupport::Testing::TimeHelpers

  let(:bake_day) { create(:bake_day, :can_order) }
  let(:customer) { create(:customer) }

  def pending_order(pi_id, customer: self.customer, bake_day: self.bake_day)
    create(:order, :pending, :with_items, customer: customer, bake_day: bake_day, payment_intent_id: pi_id)
  end

  it "releases the customer's abandoned reservation on the same bake day" do
    order = pending_order("pi_abandoned")
    stub_stripe_payment_intent_retrieve(id: "pi_abandoned", status: "requires_payment_method")
    allow(Stripe::PaymentIntent).to receive(:cancel).with("pi_abandoned")

    expect { described_class.call(customer: customer, bake_day: bake_day) }
      .to change { Order.exists?(order.id) }.from(true).to(false)
    expect(Stripe::PaymentIntent).to have_received(:cancel).with("pi_abandoned")
  end

  it "destroys an orphan reservation without payment intent once it is old enough" do
    order = pending_order(nil)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    travel_to(described_class::ORPHAN_GRACE_PERIOD.from_now + 1.second) do
      expect { described_class.call(customer: customer, bake_day: bake_day) }
        .to change { Order.exists?(order.id) }.from(true).to(false)
    end
  end

  # #261 : la commande d'une requête create_payment_intent concurrente, encore
  # en attente de Stripe, n'a pas encore de payment_intent_id. La supprimer
  # libérait son numéro et faisait échouer l'autre requête.
  it "leaves a freshly created orphan reservation untouched (concurrent request)" do
    order = pending_order(nil)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    described_class.call(customer: customer, bake_day: bake_day)

    expect(Order.exists?(order.id)).to be(true)
  end

  it "leaves a succeeded payment untouched (webhook in flight)" do
    order = pending_order("pi_paid")
    stub_stripe_payment_intent_retrieve(id: "pi_paid", status: "succeeded")

    described_class.call(customer: customer, bake_day: bake_day)

    expect(order.reload.status).to eq("pending")
  end

  it "leaves a processing payment untouched (Bancontact in flight)" do
    order = pending_order("pi_processing")
    stub_stripe_payment_intent_retrieve(id: "pi_processing", status: "processing")

    described_class.call(customer: customer, bake_day: bake_day)

    expect(order.reload.status).to eq("pending")
  end

  it "does not touch other customers' reservations" do
    other = pending_order("pi_other", customer: create(:customer))
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    described_class.call(customer: customer, bake_day: bake_day)

    expect(other.reload.status).to eq("pending")
  end

  it "does not touch the same customer's reservations on another bake day" do
    other_day = create(:bake_day, :can_order, baked_on: bake_day.baked_on + 3.days)
    order = pending_order("pi_other_day", bake_day: other_day)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    described_class.call(customer: customer, bake_day: bake_day)

    expect(order.reload.status).to eq("pending")
  end

  it "leaves the reservation in place when Stripe errors out" do
    order = pending_order("pi_error")
    allow(Stripe::PaymentIntent).to receive(:retrieve).and_raise(Stripe::APIError.new("boom"))

    described_class.call(customer: customer, bake_day: bake_day)

    expect(order.reload.status).to eq("pending")
  end
end
