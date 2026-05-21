require 'rails_helper'

RSpec.describe AuthMailer, type: :mailer do
  let(:customer) { create(:customer, first_name: "Léa", email: "lea@example.com") }

  describe '#otp' do
    subject(:mail) { described_class.otp(customer, "123456") }

    it 'is addressed to the customer email' do
      expect(mail.to).to eq(["lea@example.com"])
    end

    it 'has a login subject' do
      expect(mail.subject).to include("code de connexion")
    end

    it 'includes the code in the body' do
      expect(mail.body.encoded).to include("123456")
    end

    it 'tags the email kind as otp' do
      expect(mail["X-Email-Kind"].value).to eq("otp")
      expect(mail["X-Customer-Id"].value).to eq(customer.id.to_s)
    end

    it 'does not include an unsubscribe link' do
      expect(mail.body.encoded).not_to match(/préférences e-mail|désabonner/i)
    end

    it 'logs an EmailMessage when delivered' do
      expect { mail.deliver_now }.to change(EmailMessage, :count).by(1)
      expect(EmailMessage.last).to have_attributes(kind: "otp", to_email: "lea@example.com", customer_id: customer.id)
    end
  end
end
