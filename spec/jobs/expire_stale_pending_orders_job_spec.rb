require 'rails_helper'

RSpec.describe ExpireStalePendingOrdersJob, type: :job do
  before { allow(OrderNotificationService).to receive(:send_confirmation) }

  let(:bake_day) { create(:bake_day, :can_order) }
  let(:customer) { create(:customer) }

  def stale_pending(pi_id)
    order = create(:order, :pending, :with_items, customer: customer, bake_day: bake_day, payment_intent_id: pi_id)
    order.update_column(:created_at, 31.minutes.ago)
    order
  end

  it "deletes an abandoned reservation and frees capacity" do
    order = stale_pending("pi_abandoned")
    stub_stripe_payment_intent_retrieve(id: "pi_abandoned", status: "requires_payment_method")
    allow(Stripe::PaymentIntent).to receive(:cancel).with("pi_abandoned")

    expect { described_class.new.perform }.to change { Order.exists?(order.id) }.from(true).to(false)
    expect(Stripe::PaymentIntent).to have_received(:cancel).with("pi_abandoned")
  end

  it "finalizes a reservation whose payment actually succeeded (missed webhook)" do
    order = stale_pending("pi_paid")
    stub_stripe_payment_intent_retrieve(id: "pi_paid", status: "succeeded")

    described_class.new.perform

    expect(order.reload.status).to eq("paid")
    expect(order.payment).to be_present
  end

  it "leaves a payment still processing untouched" do
    order = stale_pending("pi_processing")
    stub_stripe_payment_intent_retrieve(id: "pi_processing", status: "processing")

    described_class.new.perform

    expect(order.reload.status).to eq("pending")
  end

  it "ignores recent pending reservations (within the grace period)" do
    order = create(:order, :pending, :with_items, customer: customer, bake_day: bake_day, payment_intent_id: "pi_recent")
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    described_class.new.perform

    expect(order.reload.status).to eq("pending")
  end

  it "ignores orders without a payment intent (e.g. cash/unpaid)" do
    order = create(:order, :unpaid, :with_items, customer: customer, bake_day: bake_day, payment_intent_id: nil)
    order.update_column(:created_at, 2.hours.ago)
    expect(Stripe::PaymentIntent).not_to receive(:retrieve)

    described_class.new.perform

    expect(order.reload.status).to eq("unpaid")
  end
end
