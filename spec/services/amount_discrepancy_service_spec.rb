require "rails_helper"

# #retour Manon : une commande dont le total ne se déduit plus de ses lignes
# produit un relevé PDF incompréhensible. Ce service dresse la liste à relire.
RSpec.describe AmountDiscrepancyService, type: :service do
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
  let(:variant) { create(:product_variant, price_cents: 450) }

  def order_with(qty:, total_cents:, customer: create(:customer), status: :unpaid, source: :admin, day: bake_day)
    create(:order, customer: customer, bake_day: day, status: status, source: source, total_cents: total_cents).tap do |order|
      create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: 450)
    end
  end

  it "ignore une commande dont le total égale la somme de ses lignes" do
    order_with(qty: 20, total_cents: 9000)

    report = described_class.new.call

    expect(report.scanned_count).to eq(1)
    expect(report).not_to be_any
  end

  # Le cas exact remonté par Manon : 18 pains à 4,50 € (81 €) enregistrés à 90 €.
  it "signale une commande dont le montant dépasse la somme de ses lignes" do
    order = order_with(qty: 18, total_cents: 9000)

    report = described_class.new.call

    expect(report.above.map(&:order)).to eq([ order ])
    expect(report.above.first.gross_cents).to eq(8100)
    expect(report.above.first.delta_cents).to eq(900)
    expect(report.unexplained_below).to be_empty
  end

  it "signale un montant sous le détail quand le client n'a aucune remise" do
    order = order_with(qty: 10, total_cents: 4000) # 45 € de lignes

    report = described_class.new.call

    expect(report.unexplained_below.map(&:order)).to eq([ order ])
    expect(report.unexplained_below.first.delta_cents).to eq(-500)
  end

  # Un client remisé descend légitimement sous le prix catalogue. Le taux du jour
  # n'étant pas conservé, on ne le liste pas — mais on le compte.
  it "ne liste pas un montant sous le détail chez un client remisé, et le compte" do
    group = create(:group, discount_percent: 10)
    customer = create(:customer)
    customer.groups << group
    order_with(qty: 10, total_cents: 4050, customer: customer)

    report = described_class.new.call

    expect(report.unexplained_below).to be_empty
    expect(report.covered_by_group_count).to eq(1)
  end

  it "signale malgré tout un montant AU-DESSUS du détail chez un client remisé" do
    group = create(:group, discount_percent: 10)
    customer = create(:customer)
    customer.groups << group
    order = order_with(qty: 10, total_cents: 5000, customer: customer)

    report = described_class.new.call

    expect(report.above.map(&:order)).to eq([ order ])
    expect(report.covered_by_group_count).to eq(0)
  end

  describe "périmètre" do
    it "exclut les commandes annulées" do
      order_with(qty: 18, total_cents: 9000, status: :cancelled)

      expect(described_class.new.call.scanned_count).to eq(0)
    end

    it "exclut les commandes en attente de paiement" do
      order_with(qty: 18, total_cents: 9000, status: :pending)

      expect(described_class.new.call.scanned_count).to eq(0)
    end

    # Les Pizza parties sont vendues au forfait : leur total ne prétend pas se
    # déduire de leurs lignes.
    it "exclut les commandes de party" do
      party = create(:party_event)
      order = create(:order, customer: create(:customer), bake_day: nil, party_event: party,
                             pickup_location: create(:pickup_location), source: :party,
                             status: :unpaid, total_cents: 2600)
      create(:order_item, order: order, product_variant: variant, qty: 2, unit_price_cents: 450)

      expect(described_class.new.call.scanned_count).to eq(0)
    end

    it "exclut les fournées brouillon" do
      draft = create(:bake_day, baked_on: Date.new(2026, 5, 19), draft: true)
      order_with(qty: 18, total_cents: 9000, day: draft)

      expect(described_class.new.call.scanned_count).to eq(0)
    end
  end

  it "classe les plus gros écarts en premier" do
    small = order_with(qty: 10, total_cents: 4600)   # +1,00 €
    big = order_with(qty: 10, total_cents: 6000)     # +15,00 €

    expect(described_class.new.call.above.map(&:order)).to eq([ big, small ])
  end
end
