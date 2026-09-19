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

  # La fenêtre est bornée par WARNING_LEAD (4 h) et non par l'heure du cron : un
  # cut-off plus lointain ne concerne pas encore le client (#292).
  describe "fenêtre de préavis" do
    it "traite une fournée dont le cut-off tombe dans 3 heures" do
      near = create(:bake_day, cut_off_at: 3.hours.from_now)
      create(:wallet, customer: customer, balance_cents: 100)
      order = create(:order, :planned, customer: customer, bake_day: near, total_cents: 5_000)

      expect(SmsService).to receive(:send_insufficient_balance_warning).with(order)
      described_class.perform_now
    end

    it "ignore une fournée dont le cut-off tombe dans 5 heures" do
      far = create(:bake_day, cut_off_at: 5.hours.from_now)
      create(:wallet, customer: customer, balance_cents: 100)
      create(:order, :planned, customer: customer, bake_day: far, total_cents: 5_000)

      expect(SmsService).not_to receive(:send_insufficient_balance_warning)
      described_class.perform_now
    end

    it "annonce sa fenêtre par une constante, pas par un littéral" do
      expect(described_class::WARNING_LEAD).to eq(4.hours)
    end
  end
end
