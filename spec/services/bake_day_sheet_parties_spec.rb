require "rails_helper"

# Les pizza parties dans la feuille compta (#274) : elles apparaissent dans le
# tableau, le total se réconcilie avec la carte « CA total », et leur CA est
# compté au NET — sans quoi toute remise consentie sur une party était
# retranchée de la marge PAIN, donc du 70/30 des boulangers.
RSpec.describe "Feuille compta — pizza parties", type: :model do
  let(:friday) { Date.new(2026, 5, 15) }
  let!(:bake_day) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }
  let(:customer) { create(:customer) }

  let(:bread) { create(:product, category: :breads, internal_category: :boulangerie, name: "Pain froment") }
  let(:bread_variant) { create(:product_variant, product: bread, name: "1 kg", price_cents: 650) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500) }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait") }
  let(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000) }

  def sell_bread(qty: 10)
    order = create(:order, :paid, customer: customer, bake_day: bake_day, total_cents: qty * 650)
    create(:order_item, order: order, product_variant: bread_variant, qty: qty, unit_price_cents: 650)
    order
  end

  # Party réservée en ligne : bake_day nil par design, rattachée par l'événement.
  def sell_party(persons: 8, total_cents: nil)
    event = create(:party_event, :private_party, held_on: friday, slot: :soir)
    gross = persons * 500 + 4_000
    order = create(:order, :paid, customer: customer, bake_day: nil, party_event: event,
                                  source: :party, total_cents: total_cents || gross)
    create(:order_item, order: order, product_variant: paton, qty: persons, unit_price_cents: 500)
    create(:order_item, order: order, product_variant: forfait, qty: 1, unit_price_cents: 4_000)
    order
  end

  subject(:sheet) { BakeDaySheetService.call(bake_day) }

  describe "présence dans le tableau" do
    before do
      sell_bread(qty: 10)
      sell_party(persons: 8)
    end

    it "fait apparaître les ventes de party sur des lignes identifiées comme telles" do
      expect(sheet.party_rows.map(&:label)).to include("Pizza party privée – une boule", "Forfait – forfait")
      expect(sheet.party_rows).to all(be_party)
      expect(sheet.bread_rows.map(&:label)).to eq([ "Pain froment – 1 kg" ])
    end

    it "réconcilie EXACTEMENT le total du tableau avec la carte « CA total »" do
      expect(sheet.total_sale_cents).to eq(sheet.day.revenue_cents)
      expect(sheet).to be_reconciled
    end

    it "distingue le sous-total pain du sous-total parties" do
      expect(sheet.bread_sale_cents).to eq(10 * 650)
      expect(sheet.party_sale_cents).to eq(8 * 500 + 4_000)
      expect(sheet.bread_sale_cents + sheet.party_sale_cents).to eq(sheet.total_sale_cents)
    end
  end

  # Le cas de la commande #1262 en production : total_cents = 600 pour 3 000 de
  # lignes brutes. Comptée au brut, la party creusait la marge pain de 2 400.
  describe "party remisée (cas #1262)" do
    let(:persons) { 4 } # 4 × 500 + 4 000 de forfait = 6 000 brut
    let(:discounted_total) { 1_200 }

    it "compte le CA party au NET, cohérent avec orders.total_cents" do
      order = sell_party(persons: persons, total_cents: discounted_total)

      result = PizzaPartyRevenueService.call([ order.reload ])

      expect(result.sale_cents).to eq(discounted_total)
      expect(result.sale_cents).to eq(order.total_cents)
    end

    it "n'ampute PAS la marge pain de l'écart de remise" do
      sell_bread(qty: 10)
      margin_without_party = BakeDaySheetService.call(bake_day).day.then do |day|
        day.revenue_cents - day.cost_price_cents - day.bread_bags_cents -
          day.transport_cents - day.commission_cents - day.sales_locations_cents
      end

      sell_party(persons: persons, total_cents: discounted_total)

      day = BakeDaySheetService.call(bake_day).day
      party_sale = day.party_revenue_cents + day.public_party_revenue_cents
      margin_with_party =
        day.revenue_cents - party_sale - day.cost_price_cents - day.bread_bags_cents -
        day.transport_cents - day.commission_cents - day.sales_locations_cents

      # La party entre dans le CA pour son net et en ressort pour le même net :
      # la marge pain est rigoureusement inchangée.
      expect(margin_with_party).to eq(margin_without_party)
    end

    it "garde le barème par personne inchangé — seul sale_cents passe au net" do
      full = PizzaPartyRevenueService.call([ sell_party(persons: persons).reload ])
      discounted = PizzaPartyRevenueService.call([ sell_party(persons: persons, total_cents: discounted_total).reload ])

      expect(discounted.persons).to eq(full.persons)
      expect(discounted.bakers_cents).to eq(full.bakers_cents)
      expect(discounted.four_sources_cents).to eq(full.four_sources_cents)
      expect(discounted.sale_cents).to be < full.sale_cents
    end
  end
end
