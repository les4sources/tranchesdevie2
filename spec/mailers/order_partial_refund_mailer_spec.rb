require 'rails_helper'

RSpec.describe OrderMailer, '#partial_refund', type: :mailer do
  let(:customer) { create(:customer, first_name: "Claire", email: "claire@example.com", email_opt_out: false) }
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 9, 18)) }
  let(:order) { create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 4_400) }
  let!(:item) { create(:order_item, order: order, qty: 6, unit_price_cents: 550) }
  let(:refund) do
    create(:partial_refund, order: order, amount_cents: 550, channel: :wallet, reason: "Pain manquant").tap do |created|
      create(:partial_refund_item, partial_refund: created, order_item: item, qty: 1, amount_cents: 550)
    end
  end

  it "détaille au client ce qui lui est rendu et où" do
    mail = described_class.partial_refund(refund)

    expect(mail.to).to eq([ "claire@example.com" ])
    expect(mail.subject).to include(order.order_number)
    expect(mail.body.encoded).to include("5,50")
    expect(mail.body.encoded).to include("portefeuille")
    expect(mail.body.encoded).to include("Pain manquant")
  end

  it "se journalise avec le genre partial_refund" do
    expect { described_class.partial_refund(refund).deliver_now }.to change(EmailMessage, :count).by(1)
    expect(EmailMessage.last.kind).to eq("partial_refund")
  end
end
