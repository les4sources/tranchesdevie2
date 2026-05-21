require 'rails_helper'

RSpec.describe OtpService do
  describe '.send_otp with channel: :email' do
    let(:phone) { "+32470111222" }

    context 'when the customer has an email on file' do
      let!(:customer) { create(:customer, phone_e164: phone, email: "eater@example.com") }

      it 'emails the code and reports success' do
        result = OtpService.send_otp(phone, channel: :email)
        expect(result[:success]).to be true
        expect(result[:channel]).to eq(:email)
      end

      it 'delivers an OTP email logged as an EmailMessage' do
        expect { OtpService.send_otp(phone, channel: :email) }
          .to change { EmailMessage.where(kind: :otp, to_email: "eater@example.com").count }.by(1)
      end

      it 'reuses the active verification code instead of creating a new one' do
        verification = PhoneVerification.create_for_phone(phone)

        expect { OtpService.send_otp(phone, channel: :email) }.not_to change(PhoneVerification, :count)
        expect(ActionMailer::Base.deliveries.last.body.encoded).to include(verification.code)
      end

      it 'creates a verification when none is active yet' do
        expect { OtpService.send_otp(phone, channel: :email) }.to change(PhoneVerification, :count).by(1)
      end
    end

    context 'when no email is on file' do
      it 'fails for a customer without an email' do
        create(:customer, phone_e164: phone, email: nil)
        result = OtpService.send_otp(phone, channel: :email)
        expect(result[:success]).to be false
        expect(result[:error]).to match(/adresse e-mail/i)
      end

      it 'fails when no customer exists for the phone' do
        result = OtpService.send_otp(phone, channel: :email)
        expect(result[:success]).to be false
        expect(result[:error]).to match(/adresse e-mail/i)
      end

      it 'does not deliver any email' do
        create(:customer, phone_e164: phone, email: nil)
        expect { OtpService.send_otp(phone, channel: :email) }.not_to change(EmailMessage, :count)
      end
    end
  end
end
