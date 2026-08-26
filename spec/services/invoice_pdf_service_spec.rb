require "rails_helper"
require "pdf/reader"

# Le PDF produit est un **relevé de commandes** (order statement) destiné à être
# joint à la facture — PAS une facture fiscale (décision produit Michael, 25/06).
# Pas de bloc TVA / HT-TTC, pas de mention « Facture ». Il porte le détail des
# articles, une invitation à consulter le détail en ligne, l'identifiant de
# connexion du client, et un QR code vers l'espace client.
RSpec.describe InvoicePdfService, type: :service do
  let(:customer) do
    create(:customer,
      first_name: "Épicerie", last_name: "Durand",
      email: "epicerie@example.com", phone_e164: "+32470000001")
  end
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

  def pdf_image_count(binary)
    PDF::Reader.new(StringIO.new(binary)).pages.sum { |page| page.xobjects.size }
  end

  it "produit un PDF non vide commençant par %PDF" do
    binary = described_class.new(invoice).render
    expect(binary).to be_present
    expect(binary).to start_with("%PDF")
  end

  it "propose un nom de fichier de relevé" do
    expect(described_class.new(invoice).filename).to eq("releve-commandes-#{invoice.number}.pdf")
  end

  describe "contenu du relevé d'une commande" do
    let(:text) { pdf_text(described_class.new(invoice).render) }

    it "s'intitule « Relevé de commandes » et n'est PAS une facture" do
      expect(text).to include("Relevé de commandes")
      expect(text).not_to match(/facture/i)
      expect(text).not_to match(/\bTVA\b/)
      expect(text).not_to match(/\bHT\b/)
      expect(text).not_to match(/\bTTC\b/)
    end

    it "contient les coordonnées boulangerie + client" do
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

    it "invite à consulter le détail des commandes en ligne" do
      expect(text).to include("Tous les détails de vos commandes sont disponibles en ligne.")
    end

    it "rappelle que la connexion reste nécessaire et affiche l'identifiant (téléphone et e-mail)" do
      expect(text).to match(/connexion|connecter/i)
      expect(text).to include("+32470000001")
      expect(text).to include("epicerie@example.com")
    end

    it "intègre un QR code (au moins une image dans le PDF)" do
      binary = described_class.new(invoice).render
      expect(pdf_image_count(binary)).to be >= 1
    end
  end

  describe "identifiant de connexion selon les coordonnées disponibles" do
    it "n'affiche que le téléphone si le client n'a pas d'e-mail" do
      customer.update!(email: nil)
      text = pdf_text(described_class.new(invoice).render)

      expect(text).to include("+32470000001")
      expect(text).not_to include("epicerie@example.com")
    end

    it "n'affiche que l'e-mail si le client n'a pas de téléphone" do
      customer.update_columns(phone_e164: nil)
      text = pdf_text(described_class.new(invoice).render)

      expect(text).to include("epicerie@example.com")
      expect(text).not_to include("+32470000001")
    end
  end

  describe "remise client sur sa propre ligne" do
    let(:group) { create(:group, name: "Épiceries", discount_percent: 10) }
    let!(:membership) { create(:customer_group, customer: customer, group: group) }

    # 3 × 5,50 € = 16,50 € au prix standard, 10 % de remise = 1,65 €, 14,85 € dus.
    let(:discounted_order) do
      create(:order, customer: customer, bake_day: bake_day, total_cents: 1485).tap do |o|
        create(:order_item, order: o, product_variant: variant, qty: 3, unit_price_cents: 550)
      end
    end
    let(:discounted_invoice) { InvoiceBuilderService.for_order(discounted_order) }
    let(:text) { pdf_text(described_class.new(discounted_invoice).render) }

    it "garde les articles au prix standard" do
      expect(text).to include("5,50")   # prix unitaire catalogue
      expect(text).to include("16,50")  # total ligne au prix standard
    end

    it "annonce le total au prix standard, puis la remise, puis le montant dû" do
      expect(text).to include("Total au prix standard")
      expect(text).to include("Remise 10 %")
      expect(text).to include("-1,65")
      expect(text).to include("14,85")
    end

    it "n'écrit aucune remise quand le client n'en a pas" do
      plain = pdf_text(described_class.new(invoice).render)

      expect(plain).not_to match(/Remise/i)
      expect(plain).not_to include("Total au prix standard")
      expect(plain).to include("16,50")
    end

    it "affiche un taux effectif à décimale avec une virgule française" do
      # Remise ciblée de 1,00 € sur la variante : 3,00 € sur 16,50 € = 18,2 %.
      discounted_order.update!(total_cents: 1350)

      expect(pdf_text(described_class.new(discounted_invoice).render)).to include("Remise 18,2 %")
    end
  end

  describe "relevé mensuel groupé par jour de cuisson (#27)" do
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

    it "détaille la remise sous le jour de cuisson concerné" do
      order_tue.update!(total_cents: 990) # 11,00 € au prix standard, 10 % de remise
      text = pdf_text(described_class.new(invoice).render)

      expect(text).to include("Sous-total au prix standard : 11,00 €")
      expect(text).to include("Remise 10 % : -1,10 €")
      expect(text).to include("Sous-total cuisson : 9,90 €")
      # Le vendredi, sans remise, garde son unique ligne de sous-total.
      expect(text).to include("Sous-total cuisson : 5,50 €")
      expect(text.scan("Sous-total au prix standard").size).to eq(1)
    end
  end
end
