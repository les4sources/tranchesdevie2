require 'rails_helper'

RSpec.describe OrderNotificationService do
  let(:bake_day) { create(:bake_day, :can_order) }

  describe '.send_confirmation' do
    context 'when the customer can receive emails' do
      let(:customer) { create(:customer, email: "eater@example.com", email_opt_out: false) }
      let(:order) { create(:order, customer: customer, bake_day: bake_day) }

      it 'sends the confirmation email' do
        delivery = double(deliver_later: true)
        expect(OrderMailer).to receive(:confirmation).with(order).and_return(delivery)
        expect(OrderNotificationService.send_confirmation(order)).to be true
      end

      it 'is idempotent when a confirmation was already logged' do
        create(:email_message, customer: customer, order: order, kind: :confirmation)
        expect(OrderMailer).not_to receive(:confirmation)
        expect(OrderNotificationService.send_confirmation(order)).to be false
      end
    end

    context 'when the customer cannot receive emails' do
      it 'does nothing without an email address' do
        customer = create(:customer, email: nil)
        order = create(:order, customer: customer, bake_day: bake_day)
        expect(OrderMailer).not_to receive(:confirmation)
        expect(OrderNotificationService.send_confirmation(order)).to be false
      end

      it 'does nothing when the customer opted out of emails' do
        customer = create(:customer, email: "eater@example.com", email_opt_out: true)
        order = create(:order, customer: customer, bake_day: bake_day)
        expect(OrderMailer).not_to receive(:confirmation)
        expect(OrderNotificationService.send_confirmation(order)).to be false
      end
    end
  end
end
