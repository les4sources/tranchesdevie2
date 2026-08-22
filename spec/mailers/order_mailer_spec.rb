require 'rails_helper'

RSpec.describe OrderMailer, type: :mailer do
  let(:customer) { create(:customer, first_name: "Marc", email: "marc@example.com") }
  let(:bake_day) { create(:bake_day, :can_order) }
  let(:order) { create(:order, :with_items, customer: customer, bake_day: bake_day) }

  describe '#confirmation' do
    subject(:mail) { described_class.confirmation(order) }

    it 'is addressed to the customer email' do
      expect(mail.to).to eq([ "marc@example.com" ])
    end

    it 'references the order number in the subject and body' do
      expect(mail.subject).to include(order.order_number)
      expect(mail.body.encoded).to include(order.order_number)
    end

    it 'lists the ordered items' do
      order.order_items.each do |item|
        expect(mail.body.encoded).to include(item.product_variant.product.name)
      end
    end

    it 'tags the email kind and order id' do
      expect(mail["X-Email-Kind"].value).to eq("confirmation")
      expect(mail["X-Order-Id"].value).to eq(order.id.to_s)
    end

    it 'includes a working unsubscribe (preferences) link' do
      html = mail.html_part.body.decoded
      expect(html).to include("/e-mails/preferences/")
      token = html[%r{/e-mails/preferences/([^"\s]+)}, 1]
      expect(Customer.find_signed(token, purpose: :email_unsubscribe)).to eq(customer)
    end

    it 'logs an EmailMessage when delivered' do
      expect { mail.deliver_now }.to change(EmailMessage, :count).by(1)
      expect(EmailMessage.last).to have_attributes(kind: "confirmation", order_id: order.id, customer_id: customer.id)
    end
  end
end
