require 'rails_helper'

RSpec.describe OrderNotificationService, '.send_ready' do
  let(:customer) { create(:customer) }
  let(:order) { create(:order, :ready, customer: customer) }

  before { allow(SmsService).to receive(:send_ready) }

  it 'sends the ready SMS' do
    expect(SmsService).to receive(:send_ready).with(order)
    described_class.send_ready(order)
  end

  it 'enqueues the ready email for an email-enabled customer' do
    mail = double(deliver_later: true)
    expect(OrderMailer).to receive(:ready).with(order).and_return(mail)
    described_class.send_ready(order)
  end

  it 'does not email a customer without an email' do
    no_email = create(:customer, :without_email)
    order_no_email = create(:order, :ready, customer: no_email)
    expect(OrderMailer).not_to receive(:ready)
    described_class.send_ready(order_no_email)
  end

  it 'does not send a duplicate ready email' do
    create(:email_message, order: order, customer: customer, kind: :ready)
    expect(OrderMailer).not_to receive(:ready)
    described_class.send_ready(order)
  end
end

RSpec.describe OrderMailer, type: :mailer do
  describe '#ready' do
    let(:customer) { create(:customer, first_name: 'Alex') }
    let(:order) { create(:order, :ready, customer: customer) }

    it 'uses the editable subject and body and tags the email kind' do
      NotificationSetting.current.update!(
        ready_email_subject: 'Ta commande est prête !',
        ready_sms_body: 'Corps de message éditable'
      )
      allow(order).to receive(:unpaid_ready?).and_return(false)

      mail = OrderMailer.ready(order)

      expect(mail.subject).to eq('Ta commande est prête !')
      expect(mail.to).to eq([customer.email])
      expect(mail.body.encoded).to include('Corps de message éditable')
      expect(mail['X-Email-Kind'].value).to eq('ready')
    end
  end
end
