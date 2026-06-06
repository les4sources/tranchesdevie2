require 'rails_helper'

RSpec.describe StripeFeeService do
  let(:payment) { create(:payment, stripe_payment_intent_id: 'pi_test_fee', stripe_fee_cents: nil) }

  def stub_charge(balance_transaction:)
    charge = double('Stripe::Charge', balance_transaction: balance_transaction)
    list = double('Stripe::ListObject', data: [ charge ])
    allow(Stripe::Charge).to receive(:list)
      .with(payment_intent: 'pi_test_fee', limit: 1)
      .and_return(list)
  end

  describe '.fetch_for' do
    it 'retrieves the fee from the balance transaction and stores it' do
      stub_charge(balance_transaction: 'txn_123')
      allow(Stripe::BalanceTransaction).to receive(:retrieve).with('txn_123')
        .and_return(double('Stripe::BalanceTransaction', fee: 42))

      result = described_class.fetch_for(payment)

      expect(result).to eq(42)
      expect(payment.reload.stripe_fee_cents).to eq(42)
    end

    it 'does not call the Stripe API when the fee is already recorded' do
      payment.update!(stripe_fee_cents: 30)
      expect(Stripe::Charge).not_to receive(:list)

      expect(described_class.fetch_for(payment)).to eq(30)
    end

    it 'returns nil and stores nothing when there is no charge yet' do
      list = double('Stripe::ListObject', data: [])
      allow(Stripe::Charge).to receive(:list).and_return(list)

      expect(described_class.fetch_for(payment)).to be_nil
      expect(payment.reload.stripe_fee_cents).to be_nil
    end

    it 'returns nil when the charge has no balance transaction yet' do
      stub_charge(balance_transaction: nil)

      expect(described_class.fetch_for(payment)).to be_nil
      expect(payment.reload.stripe_fee_cents).to be_nil
    end

    it 'swallows Stripe errors and returns nil' do
      allow(Stripe::Charge).to receive(:list).and_raise(Stripe::StripeError.new('boom'))

      expect(described_class.fetch_for(payment)).to be_nil
      expect(payment.reload.stripe_fee_cents).to be_nil
    end
  end
end
