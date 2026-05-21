require 'rails_helper'

RSpec.describe EmailMessage, type: :model do
  it 'is valid with the required attributes' do
    expect(build(:email_message)).to be_valid
  end

  it 'requires a recipient, sender and body' do
    message = EmailMessage.new
    message.valid?
    expect(message.errors[:to_email]).to be_present
    expect(message.errors[:from_email]).to be_present
    expect(message.errors[:body_html]).to be_present
  end

  it 'exposes confirmation, otp and other kinds' do
    expect(EmailMessage.kinds.keys).to contain_exactly("confirmation", "otp", "other")
  end

  it 'belongs optionally to a customer and an order' do
    expect(build(:email_message, customer: nil, order: nil)).to be_valid
  end
end
