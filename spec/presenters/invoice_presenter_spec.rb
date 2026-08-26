require "rails_helper"

RSpec.describe InvoicePresenter do
  let(:customer) { create(:customer) }
  let(:product) { create(:product, name: "Pain froment") }
  let(:variant) { create(:product_variant, product: product, name: "Petit 600 g", price_cents: 550) }

  def order_on(bake_day, qty:)
    create(:order, customer: customer, bake_day: bake_day, total_cents: 550 * qty).tap do |o|
      create(:order_item, order: o, product_variant: variant, qty: qty, unit_price_cents: 550)
    end
  end

  describe "lignes d'une facture commande unique" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:order) { order_on(bake_day, qty: 3) }
    let(:invoice) { InvoiceBuilderService.for_order(order) }

    it "expose le libellé produit + variante, quantité, prix et total" do
      line = described_class.new(invoice).lines.first

      expect(line.label).to eq("Pain froment — Petit 600 g")
      expect(line.quantity).to eq(3)
      expect(line.unit_price_cents).to eq(550)
      expect(line.total_cents).to eq(1650)
    end
  end

  describe "remise client exposée à part du prix standard" do
    let(:group) { create(:group, name: "Épiceries", discount_percent: 10) }
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }

    # Les lignes portent le prix STANDARD (cf. OrderCreationService) ; seul
    # `orders.total_cents` est net de remise. Ici : 3 × 5,50 € = 16,50 € brut,
    # 10 % de remise = 1,65 €, donc 14,85 € dus.
    let!(:membership) { create(:customer_group, customer: customer, group: group) }
    let(:order) do
      create(:order, customer: customer, bake_day: bake_day, total_cents: 1485).tap do |o|
        create(:order_item, order: o, product_variant: variant, qty: 3, unit_price_cents: 550)
      end
    end
    let(:invoice) { InvoiceBuilderService.for_order(order) }
    let(:presenter) { described_class.new(invoice) }

    it "expose le montant au prix standard, la remise et le montant dû" do
      expect(presenter.gross_cents).to eq(1650)
      expect(presenter.discount_cents).to eq(165)
      expect(presenter.discount_percent).to eq(10.0)
      expect(presenter.total_cents).to eq(1485)
      expect(presenter).to be_discount_applied
    end

    it "laisse les lignes au prix standard, jamais au prix réduit" do
      line = presenter.lines.first

      expect(line.unit_price_cents).to eq(550)
      expect(line.total_cents).to eq(1650)
    end

    it "reflète la remise de la commande, pas les groupes actuels du client" do
      invoice # relevé émis avec la remise du jour
      group.update!(discount_percent: 50)

      expect(described_class.new(invoice).discount_cents).to eq(165)
      expect(described_class.new(invoice).discount_percent).to eq(10.0)
    end
  end

  describe "sans remise" do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:order) { order_on(bake_day, qty: 3) }
    let(:presenter) { described_class.new(InvoiceBuilderService.for_order(order)) }

    it "n'annonce aucune remise et laisse le total inchangé" do
      expect(presenter.gross_cents).to eq(1650)
      expect(presenter.discount_cents).to eq(0)
      expect(presenter.discount_percent).to eq(0.0)
      expect(presenter).not_to be_discount_applied
    end
  end

  describe "groupes par jour de cuisson (#27)" do
    let(:tuesday) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:friday) { create(:bake_day, baked_on: Date.new(2026, 5, 15)) }
    let!(:order_tue) { order_on(tuesday, qty: 2) }
    let!(:order_fri) { order_on(friday, qty: 1) }

    let(:invoice) do
      InvoiceBuilderService.for_customer_month(customer: customer, month: Date.new(2026, 5, 1))
    end

    it "regroupe les commandes par jour de cuisson, dans l'ordre chronologique" do
      groups = described_class.new(invoice).bake_day_groups

      expect(groups.map(&:baked_on)).to eq([ Date.new(2026, 5, 12), Date.new(2026, 5, 15) ])
      expect(groups.first.total_cents).to eq(1100)
      expect(groups.last.total_cents).to eq(550)
    end

    it "identifie chaque groupe par ses numéros de commande" do
      groups = described_class.new(invoice).bake_day_groups

      expect(groups.first.order_numbers).to include(order_tue.order_number)
      expect(groups.last.order_numbers).to include(order_fri.order_number)
    end

    it "porte le prix standard et la remise sur chaque jour de cuisson" do
      # Le mardi est remisé de 10 % (11,00 € brut → 9,90 €), le vendredi non.
      order_tue.update!(total_cents: 990)
      groups = described_class.new(invoice).bake_day_groups

      expect(groups.first.gross_cents).to eq(1100)
      expect(groups.first.discount_cents).to eq(110)
      expect(groups.first.discount_percent).to eq(10.0)
      expect(groups.first.total_cents).to eq(990)

      expect(groups.last).not_to be_discount_applied
      expect(groups.last.gross_cents).to eq(550)
      expect(groups.last.total_cents).to eq(550)
    end
  end
end
