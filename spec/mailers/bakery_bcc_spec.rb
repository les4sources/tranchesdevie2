require 'rails_helper'

# Copie cachée sur tout ce qui part à la boulangerie.
#
# L'intercepteur agit à la LIVRAISON, donc au-dessus de tous les mailers :
# c'est ce qui garantit qu'un e-mail écrit demain sera copié lui aussi.
RSpec.describe BakeryBccInterceptor do
  let!(:default_pickup) { create(:pickup_location, name: "Les 4 Sources", default: true) }
  let!(:party_product) { create(:product, :pizza_party) }
  let!(:party_variant) { create(:product_variant, product: party_product, price_cents: 1200) }
  let!(:forfait_product) { create(:product, :pizza_party_forfait) }
  let!(:forfait_variant) { create(:product_variant, product: forfait_product, price_cents: 4000, channel: "admin") }

  let(:customer) { create(:customer, first_name: "Camille", email: "camille@example.com") }
  let(:party_request) { create(:party_request, customer: customer) }

  def deliver(mail)
    mail.deliver_now
    ActionMailer::Base.deliveries.last
  end

  before { ActionMailer::Base.deliveries.clear }

  it "copie Michael sur un e-mail adressé à la boulangerie" do
    delivered = deliver(PartyRequestMailer.new_request(party_request))

    expect(delivered.to).to include(described_class.watched_address)
    expect(delivered.bcc).to include("michael+tranchesdevie@hulet.eu")
  end

  it "ne copie PAS un e-mail adressé au client" do
    delivered = deliver(PartyRequestMailer.received(party_request))

    expect(delivered.to).to eq([ "camille@example.com" ])
    expect(Array(delivered.bcc)).to be_empty
  end

  it "ne pose pas deux fois la même copie" do
    delivered = deliver(PartyRequestMailer.new_request(party_request))

    expect(delivered.bcc.count { |a| a == "michael+tranchesdevie@hulet.eu" }).to eq(1)
  end

  it "reste silencieux quand l'adresse de copie est vide" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("BAKERY_BCC", anything).and_return("")

    delivered = deliver(PartyRequestMailer.new_request(party_request))

    expect(Array(delivered.bcc)).to be_empty
  end

  it "suit l'adresse surveillée quand elle est redéfinie" do
    message = Mail.new(to: "quelquun@ailleurs.be", subject: "x", body: "y")
    described_class.delivering_email(message)

    expect(Array(message.bcc)).to be_empty
  end
end
