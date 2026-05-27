require 'rails_helper'

# ISC-57: pre-cut-off job warns customers whose wallet can't cover a planned order.
RSpec.describe CheckInsufficientBalanceJob, type: :job do
  before { allow(SlackService).to receive(:send_message) }

  let(:bake_day) { create(:bake_day, cut_off_at: 2.hours.from_now) }
  let(:customer) { create(:customer) }

  it 'warns a customer whose wallet cannot cover the planned order' do
    create(:wallet, customer: customer, balance_cents: 100)
    order = create(:order, :planned, customer: customer, bake_day: bake_day, total_cents: 5_000)
    expect(SmsService).to receive(:send_insufficient_balance_warning).with(order)
    described_class.perform_now
  end

  it 'does not warn when the wallet can cover the order' do
    create(:wallet, customer: customer, balance_cents: 10_000)
    create(:order, :planned, customer: customer, bake_day: bake_day, total_cents: 5_000)
    expect(SmsService).not_to receive(:send_insufficient_balance_warning)
    described_class.perform_now
  end
end
