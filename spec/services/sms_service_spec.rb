require 'rails_helper'

RSpec.describe SmsService do
  let(:customer) { create(:customer, sms_opt_out: false) }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:order) { create(:order, customer: customer, bake_day: bake_day, total_cents: 1500) }
  let(:wallet) { create(:wallet, customer: customer, balance_cents: 500) }

  before do
    # Stub environment variables for SMS service
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SMSTOOLS_CLIENT_ID').and_return('test_client_id')
    allow(ENV).to receive(:[]).with('SMSTOOLS_CLIENT_SECRET').and_return('test_client_secret')
    allow(ENV).to receive(:[]).with('SMSTOOLS_SENDER').and_return('TranchesDeVie')

    # Stub HTTParty to prevent actual API calls
    allow(HTTParty).to receive(:post).and_return(
      double(success?: true, code: 200, :[] => 'msg_123', body: '{"messageid": "msg_123"}')
    )
  end

  describe '.send_planned_order_confirmed' do
    it 'sends an SMS with the debited amount' do
      expect(HTTParty).to receive(:post).with(
        SmsService::SMSTOOLS_API_URL,
        hash_including(
          body: a_string_matching(/15.*débité/)
        )
      ).and_return(double(success?: true, code: 200, :[] => 'msg_123', body: '{}'))

      SmsService.send_planned_order_confirmed(order)
    end

    it 'includes the bake date in the message' do
      expect(HTTParty).to receive(:post).with(
        SmsService::SMSTOOLS_API_URL,
        hash_including(
          body: a_string_matching(/#{I18n.l(bake_day.baked_on, format: :long)}/)
        )
      ).and_return(double(success?: true, code: 200, :[] => 'msg_123', body: '{}'))

      SmsService.send_planned_order_confirmed(order)
    end

    it 'creates an SmsMessage record' do
      expect {
        SmsService.send_planned_order_confirmed(order)
      }.to change(SmsMessage, :count).by(1)
    end

    it 'returns false if customer has SMS disabled' do
      customer.update!(sms_opt_out: true)
      expect(SmsService.send_planned_order_confirmed(order)).to be false
    end
  end

  describe '.send_planned_order_cancelled' do
    it 'sends an SMS mentioning insufficient balance' do
      expect(HTTParty).to receive(:post).with(
        SmsService::SMSTOOLS_API_URL,
        hash_including(
          body: a_string_matching(/solde.*insuffisant/i)
        )
      ).and_return(double(success?: true, code: 200, :[] => 'msg_123', body: '{}'))

      SmsService.send_planned_order_cancelled(order)
    end

    it 'creates an SmsMessage record' do
      expect {
        SmsService.send_planned_order_cancelled(order)
      }.to change(SmsMessage, :count).by(1)
    end

    it 'returns false if customer has SMS disabled' do
      customer.update!(sms_opt_out: true)
      expect(SmsService.send_planned_order_cancelled(order)).to be false
    end
  end

  describe '.send_insufficient_balance_warning' do
    before { wallet }

    it 'sends an SMS with the missing amount' do
      # Order total is 1500 cents, wallet has 500 cents
      # Missing: 1000 cents = 10€
      expect(HTTParty).to receive(:post).with(
        SmsService::SMSTOOLS_API_URL,
        hash_including(
          body: a_string_matching(/manque.*10/)
        )
      ).and_return(double(success?: true, code: 200, :[] => 'msg_123', body: '{}'))

      SmsService.send_insufficient_balance_warning(order)
    end

    it 'includes the bake date in the message' do
      expect(HTTParty).to receive(:post).with(
        SmsService::SMSTOOLS_API_URL,
        hash_including(
          body: a_string_matching(/#{I18n.l(bake_day.baked_on, format: :long)}/)
        )
      ).and_return(double(success?: true, code: 200, :[] => 'msg_123', body: '{}'))

      SmsService.send_insufficient_balance_warning(order)
    end

    it 'creates an SmsMessage record' do
      expect {
        SmsService.send_insufficient_balance_warning(order)
      }.to change(SmsMessage, :count).by(1)
    end

    it 'returns false if customer has SMS disabled' do
      customer.update!(sms_opt_out: true)
      expect(SmsService.send_insufficient_balance_warning(order)).to be false
    end
  end

  describe '.send_low_balance_alert' do
    before { wallet }

    it 'sends an SMS with the current balance' do
      expect(HTTParty).to receive(:post).with(
        SmsService::SMSTOOLS_API_URL,
        hash_including(
          body: a_string_matching(/5.*€/)
        )
      ).and_return(double(success?: true, code: 200, :[] => 'msg_123', body: '{}'))

      SmsService.send_low_balance_alert(customer)
    end

    it 'creates an SmsMessage record' do
      expect {
        SmsService.send_low_balance_alert(customer)
      }.to change(SmsMessage, :count).by(1)
    end

    it 'returns false if customer has SMS disabled' do
      customer.update!(sms_opt_out: true)
      expect(SmsService.send_low_balance_alert(customer)).to be false
    end

    it 'returns false if customer has no wallet' do
      customer_without_wallet = create(:customer, sms_opt_out: false)
      expect(SmsService.send_low_balance_alert(customer_without_wallet)).to be false
    end
  end
end
