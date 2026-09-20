require 'rails_helper'

RSpec.describe OrderIssueMailer, type: :mailer do
  let(:customer) { create(:customer, first_name: "Claire", last_name: "Dupont") }
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 9, 18)) }
  let(:order) { create(:order, :ready, customer: customer, bake_day: bake_day, total_cents: 4_400) }
  let!(:item) { create(:order_item, order: order, qty: 6, unit_price_cents: 550) }
  let(:issue) do
    create(:order_issue, order: order, customer: customer, description: "Il manquait un froment aux graines.").tap do |created|
      create(:order_issue_item, order_issue: created, order_item: item, qty: 1)
    end
  end

  it "part à l'équipe boulangère avec le détail et le lien admin" do
    mail = described_class.reported(issue)

    expect(mail.to).to eq([ ENV.fetch("BAKERY_NOTIFICATION_ADDRESS", "boulangerie@les4sources.be") ])
    expect(mail.subject).to include(order.order_number)
    expect(mail.subject).to include("Claire Dupont")
    expect(mail.body.encoded).to include("Il manquait un froment aux graines.")
    expect(mail.body.encoded).to include("1 ×")
    expect(mail.body.encoded).to include("/admin/orders/#{order.id}")
  end

  it "se journalise comme notification interne, sans client attaché" do
    expect { described_class.reported(issue).deliver_now }.to change(EmailMessage, :count).by(1)

    logged = EmailMessage.last
    expect(logged.kind).to eq("order_issue_reported")
    expect(logged.order_id).to eq(order.id)
    expect(logged.customer_id).to be_nil
  end
end
