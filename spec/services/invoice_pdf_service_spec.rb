require "rails_helper"
require "pdf/reader"

RSpec.describe InvoicePdfService, type: :service do
  let(:customer) { create(:customer, first_name: "Épicerie", last_name: "Durand", email: "epicerie@example.com") }
  let(:product) { create(:product, name: "Pain froment") }
  let(:variant) { create(:product_variant, product: product, name: "Petit 600 g", price_cents: 550) }
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
  let(:order) do
    create(:order, customer: customer, bake_day: bake_day, total_cents: 1650).tap do |o|
      create(:order_item, order: o, product_variant: variant, qty: 3, unit_price_cents: 550)
    end
  end
  let(:invoice) { InvoiceBuilderService.for_order(order) }

  def pdf_text(binary)
    PDF::Reader.new(StringIO.new(binary)).pages.map(&:text).join("\n")
  end

  it "produit un PDF non vide commençant par %PDF" do
    binary = described_class.new(invoice).render
    expect(binary).to be_present
    expect(binary).to start_with("%PDF")
  end

  it "propose un nom de fichier basé sur le numéro de facture" do
    expect(described_class.new(invoice).filename).to eq("facture-#{invoice.number}.pdf")
  end

  describe "contenu de la facture d'une commande" do
    let(:text) { pdf_text(described_class.new(invoice).render) }

    it "contient le numéro de facture et les coordonnées boulangerie + client" do
      expect(text).to include(invoice.number)
      expect(text).to include(BakeryDetails::NAME)
      expect(text).to include("Épicerie Durand")
    end

    it "contient le nom du produit et la variante" do
      expect(text).to include("Pain froment")
      expect(text).to include("Petit 600 g")
    end

    it "contient les quantités, prix unitaire et total ligne" do
      expect(text).to match(/\b3\b/)          # quantité
      expect(text).to include("5,50")          # prix unitaire
      expect(text).to include("16,50")         # total ligne / total
    end

    it "contient le total" do
      expect(text).to include("16,50")
    end
  end

  describe "facture mensuelle groupée par jour de cuisson (#27)" do
    let(:tuesday) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:friday) { create(:bake_day, baked_on: Date.new(2026, 5, 15)) }

    let!(:order_tue) do
      create(:order, customer: customer, bake_day: tuesday, total_cents: 1100).tap do |o|
        create(:order_item, order: o, product_variant: variant, qty: 2, unit_price_cents: 550)
      end
    end
    let!(:order_fri) do
      create(:order, customer: customer, bake_day: friday, total_cents: 550).tap do |o|
        create(:order_item, order: o, product_variant: variant, qty: 1, unit_price_cents: 550)
      end
    end

    let(:invoice) do
      InvoiceBuilderService.for_customer_month(customer: customer, month: Date.new(2026, 5, 1))
    end

    it "identifie chaque jour de cuisson dans le PDF" do
      text = pdf_text(described_class.new(invoice).render)

      expect(text).to include(I18n.l(Date.new(2026, 5, 12)))
      expect(text).to include(I18n.l(Date.new(2026, 5, 15)))
    end
  end
end
