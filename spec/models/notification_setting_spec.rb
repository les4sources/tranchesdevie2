require 'rails_helper'

RSpec.describe NotificationSetting, type: :model do
  describe '.current' do
    it 'returns a singleton, creating it once with defaults' do
      first = NotificationSetting.current
      expect(NotificationSetting.current.id).to eq(first.id)
      expect(NotificationSetting.count).to eq(1)
    end

    it 'seeds defaults reproducing the historical hardcoded ready texts' do
      setting = NotificationSetting.current
      expect(setting.ready_sms_body).to eq(NotificationSetting::DEFAULT_READY_SMS_BODY)
      expect(setting.ready_sms_body_unpaid).to eq(NotificationSetting::DEFAULT_READY_SMS_BODY_UNPAID)
      expect(setting.ready_email_subject).to be_present
    end
  end

  describe 'singleton guard' do
    it 'refuses to persist a second record' do
      NotificationSetting.current
      expect(NotificationSetting.new(ready_sms_body: 'x').save).to be(false)
    end
  end

  describe '#rendered_ready_message' do
    let(:customer) { create(:customer, first_name: 'Camille') }

    it 'renders the paid variant for a paid order' do
      order = create(:order, :paid, customer: customer)
      allow(order).to receive(:unpaid_ready?).and_return(false)
      expect(NotificationSetting.current.rendered_ready_message(order))
        .to eq(NotificationSetting::DEFAULT_READY_SMS_BODY)
    end

    it 'renders the unpaid variant with the formatted amount (non-round)' do
      order = create(:order, :ready, customer: customer, total_cents: 1250)
      allow(order).to receive(:unpaid_ready?).and_return(true)
      msg = NotificationSetting.current.rendered_ready_message(order)
      expect(msg).to include('12,50 €')
      expect(msg).not_to include('{montant}')
    end

    it 'interpolates {prenom} and {numero}' do
      setting = NotificationSetting.current
      setting.update!(ready_sms_body: 'Salut {prenom}, commande {numero} prête')
      order = create(:order, :paid, customer: customer)
      allow(order).to receive(:unpaid_ready?).and_return(false)
      msg = setting.rendered_ready_message(order)
      expect(msg).to include('Salut Camille')
      expect(msg).to include(order.order_number)
    end

    it 'does not raise on an unknown variable (renders empty)' do
      setting = NotificationSetting.current
      setting.update!(ready_sms_body: 'Hello {inconnue}!')
      order = create(:order, :paid, customer: customer)
      allow(order).to receive(:unpaid_ready?).and_return(false)
      expect { setting.rendered_ready_message(order) }.not_to raise_error
      expect(setting.rendered_ready_message(order)).to eq('Hello !')
    end
  end
end
