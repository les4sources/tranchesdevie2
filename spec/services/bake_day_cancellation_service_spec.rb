require "rails_helper"

RSpec.describe BakeDayCancellationService do
  let(:bake_day) { create(:bake_day, :cut_off_passed) }

  before { allow(SmsService).to receive(:send_bake_cancelled).and_return(true) }

  def stripe_order(status: :paid, total_cents: 1100)
    order = create(:order, status, bake_day: bake_day, total_cents: total_cents)
    create(:payment, order: order)
    order
  end

  def wallet_order(status: :paid, total_cents: 1100, balance_cents: 5000)
    customer = create(:customer)
    wallet = create(:wallet, customer: customer, balance_cents: balance_cents)
    order = create(:order, status, customer: customer, bake_day: bake_day, total_cents: total_cents)
    create(:wallet_transaction, :order_debit, wallet: wallet, order: order)
    order
  end

  describe "#call" do
    context "with a Stripe-paid order" do
      let!(:order) { stripe_order }

      before { stub_stripe_refund_create(payment_intent_id: order.payment.stripe_payment_intent_id) }

      it "issues a Stripe refund" do
        expect(Stripe::Refund).to receive(:create)
          .with(payment_intent: order.payment.stripe_payment_intent_id)
          .and_return(double(status: "succeeded"))
        described_class.new(bake_day).call
      end

      it "marks the payment refunded and cancels the order" do
        described_class.new(bake_day).call
        expect(order.reload.status).to eq("cancelled")
        expect(order.payment.reload.status).to eq("refunded")
      end

      it "notifies the customer that they were refunded" do
        expect(SmsService).to receive(:send_bake_cancelled).with(order, refunded: true)
        described_class.new(bake_day).call
      end

      it "reports the refund in the result" do
        result = described_class.new(bake_day).call
        expect(result.stripe_refunds_count).to eq(1)
        expect(result.refunded_cents).to eq(1100)
        expect(result).to be_success
      end
    end

    context "with a wallet-paid order" do
      let!(:order) { wallet_order(balance_cents: 0) }

      it "credits the wallet back and cancels the order" do
        described_class.new(bake_day).call
        expect(order.reload.status).to eq("cancelled")
        expect(order.customer.wallet.reload.balance_cents).to eq(1100)
        expect(order.wallet_transactions.where(transaction_type: :order_refund)).to exist
      end

      it "reports the wallet refund and notifies the customer" do
        expect(SmsService).to receive(:send_bake_cancelled).with(order, refunded: true)
        result = described_class.new(bake_day).call
        expect(result.wallet_refunds_count).to eq(1)
        expect(result.refunded_cents).to eq(1100)
      end

      it "does not touch Stripe" do
        expect(Stripe::Refund).not_to receive(:create)
        described_class.new(bake_day).call
      end
    end

    context "with an unpaid order (nothing collected)" do
      let!(:order) { create(:order, :unpaid, bake_day: bake_day) }

      it "cancels it without any refund and notifies without promising a refund" do
        expect(SmsService).to receive(:send_bake_cancelled).with(order, refunded: false)
        result = described_class.new(bake_day).call
        expect(order.reload.status).to eq("cancelled")
        expect(result.cancelled_without_refund_count).to eq(1)
        expect(result.refunded_count).to eq(0)
      end
    end

    context "with a paid order with no online payment trace (offline cash)" do
      # Paiement hors-ligne marqué manuellement payé (payment_status), sans trace
      # Stripe/portefeuille (#97 : « payé » = paiement réel/marquage, pas le statut).
      let!(:order) { create(:order, :paid, :payment_paid, bake_day: bake_day) }

      it "cancels it and flags it for a manual refund" do
        result = described_class.new(bake_day).call
        expect(order.reload.status).to eq("cancelled")
        expect(result.manual_refund_orders).to eq([ order.order_number ])
        expect(result.refunded_count).to eq(0)
      end
    end

    context "with a ready order" do
      let!(:order) { stripe_order(status: :ready) }

      before { stub_stripe_refund_create(payment_intent_id: order.payment.stripe_payment_intent_id) }

      it "still refunds and cancels it" do
        described_class.new(bake_day).call
        expect(order.reload.status).to eq("cancelled")
      end
    end

    context "with already-finished orders" do
      let!(:picked_up) { create(:order, :picked_up, bake_day: bake_day) }
      let!(:cancelled) { create(:order, :cancelled, bake_day: bake_day) }

      it "leaves them untouched" do
        described_class.new(bake_day).call
        expect(picked_up.reload.status).to eq("picked_up")
        expect(cancelled.reload.status).to eq("cancelled")
      end
    end

    context "when a customer has SMS disabled" do
      let!(:order) do
        customer = create(:customer, :with_sms_disabled)
        wallet = create(:wallet, customer: customer, balance_cents: 0)
        o = create(:order, :paid, customer: customer, bake_day: bake_day)
        create(:wallet_transaction, :order_debit, wallet: wallet, order: o)
        o
      end

      it "still refunds and cancels, without sending an SMS" do
        expect(SmsService).not_to receive(:send_bake_cancelled)
        described_class.new(bake_day).call
        expect(order.reload.status).to eq("cancelled")
        expect(order.customer.wallet.reload.balance_cents).to eq(1100)
      end
    end

    context "with a pending Stripe refund (async method like Bancontact)" do
      let!(:order) { stripe_order }

      before { stub_stripe_refund_create(payment_intent_id: order.payment.stripe_payment_intent_id, status: "pending") }

      it "treats it as a success: refunds, cancels and notifies" do
        expect(SmsService).to receive(:send_bake_cancelled).with(order, refunded: true)
        result = described_class.new(bake_day).call
        expect(order.reload.status).to eq("cancelled")
        expect(order.payment.reload.status).to eq("refunded")
        expect(result.stripe_refunds_count).to eq(1)
        expect(result).to be_success
      end
    end

    context "when a Stripe refund actually fails" do
      let!(:order) { stripe_order }

      before { stub_stripe_refund_create(payment_intent_id: order.payment.stripe_payment_intent_id, status: "failed") }

      it "records a failure and leaves the order untouched" do
        result = described_class.new(bake_day).call
        expect(result).not_to be_success
        expect(result.failures.first[:order]).to eq(order.order_number)
        expect(order.reload.status).to eq("paid")
        expect(order.payment.reload.status).to eq("succeeded")
      end

      it "does not notify the customer for the failed order" do
        expect(SmsService).not_to receive(:send_bake_cancelled)
        described_class.new(bake_day).call
      end
    end

    context "with a mix of payment methods" do
      let!(:stripe) { stripe_order(total_cents: 1000) }
      let!(:wallet) { wallet_order(total_cents: 2000, balance_cents: 0) }
      let!(:unpaid) { create(:order, :unpaid, bake_day: bake_day) }

      before { stub_stripe_refund_create(payment_intent_id: stripe.payment.stripe_payment_intent_id) }

      it "aggregates every cohort in the result" do
        result = described_class.new(bake_day).call
        expect(result.stripe_refunds_count).to eq(1)
        expect(result.wallet_refunds_count).to eq(1)
        expect(result.refunded_cents).to eq(3000)
        expect(result.cancelled_without_refund_count).to eq(1)
        expect(result.total_cancelled_count).to eq(3)
        expect(result).to be_success
      end
    end
  end
end
