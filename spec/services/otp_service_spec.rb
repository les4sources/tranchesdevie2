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

    context 'when the customer has an email on file and a different address is typed' do
      let!(:customer) { create(:customer, phone_e164: phone, email: "onfile@example.com") }

      it 'always sends to the on-file address (typed address is ignored)' do
        OtpService.send_otp(phone, channel: :email, email: "attacker@example.com", allow_email_entry: true)
        expect(ActionMailer::Base.deliveries.last.to).to eq([ "onfile@example.com" ])
      end
    end

    context 'when the customer exists but has no email on file' do
      before { create(:customer, phone_e164: phone, email: nil) }

      it 'is not eligible, even with a typed address' do
        result = OtpService.send_otp(phone, channel: :email, email: "typed@example.com", allow_email_entry: true)
        expect(result[:success]).to be false
        expect(result[:error]).to match(/contacte-nous/i)
      end

      it 'does not deliver any email' do
        expect {
          OtpService.send_otp(phone, channel: :email, email: "typed@example.com", allow_email_entry: true)
        }.not_to change(EmailMessage, :count)
      end
    end

    context 'when the phone is not registered yet' do
      it 'fails by default (allow_email_entry false), e.g. on the login page' do
        result = OtpService.send_otp(phone, channel: :email, email: "newcomer@example.com")
        expect(result[:success]).to be false
        expect(result[:error]).to match(/contacte-nous/i)
      end

      it 'asks for an email when entry is allowed but none is provided' do
        result = OtpService.send_otp(phone, channel: :email, allow_email_entry: true)
        expect(result[:success]).to be false
        expect(result[:need_email]).to be true
      end

      it 'rejects an invalid typed email' do
        result = OtpService.send_otp(phone, channel: :email, email: "not-an-email", allow_email_entry: true)
        expect(result[:success]).to be false
        expect(result[:need_email]).to be true
      end

      it 'sends the code to the typed email when entry is allowed' do
        result = OtpService.send_otp(phone, channel: :email, email: "newcomer@example.com", allow_email_entry: true)
        expect(result[:success]).to be true
        expect(result[:email]).to eq("newcomer@example.com")
        expect(ActionMailer::Base.deliveries.last.to).to eq([ "newcomer@example.com" ])
      end

      it 'logs the email without a customer' do
        expect {
          OtpService.send_otp(phone, channel: :email, email: "newcomer@example.com", allow_email_entry: true)
        }.to change { EmailMessage.where(kind: :otp, to_email: "newcomer@example.com", customer_id: nil).count }.by(1)
      end
    end
  end
end
