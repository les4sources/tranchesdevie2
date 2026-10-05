require "rails_helper"
require "pdf/reader"

# Bon de livraison d'une commande : part avec les pains, signé à la réception.
RSpec.describe DeliveryNotePdfService, type: :service do
  let(:customer) do
    create(:customer,
      first_name: "Épicerie", last_name: "Durand",
      email: "epicerie@example.com", phone_e164: "+32470000001")
  end
  let(:froment) { create(:product_variant, product: create(:product, name: "Pain froment"), name: "Petit 600 g", price_cents: 550) }
  let(:epeautre) { create(:product_variant, product: create(:product, name: "Pain épeautre"), name: "Grand 1 kg", price_cents: 800) }
  let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
  let(:total_cents) { 3250 }
  let(:order) do
    create(:order, customer: customer, bake_day: bake_day, total_cents: total_cents, customer_note: "Livrer à l'arrière").tap do |o|
      create(:order_item, order: o, product_variant: froment, qty: 3, unit_price_cents: 550)
      create(:order_item, order: o, product_variant: epeautre, qty: 2, unit_price_cents: 800)
    end
  end

  let(:service) { described_class.new(order) }
  let(:text) { PDF::Reader.new(StringIO.new(service.render)).pages.map(&:text).join("\n") }

  it "produit un PDF" do
    expect(service.render).to start_with("%PDF")
  end

  it "dérive son numéro et son nom de fichier du numéro de commande" do
    expect(service.number).to eq("BL-#{order.order_number.delete_prefix('TV-')}")
    expect(service.filename).to eq("bon-de-livraison-#{service.number}.pdf")
  end

  it "porte le titre, le numéro de bon et la commande" do
    expect(text).to include("BON DE LIVRAISON")
    expect(text).to include(service.number)
    expect(text).to include(order.order_number)
  end

  it "indique la date de production" do
    expect(text).to include("Mardi 12 mai 2026")
  end

  it "contient les coordonnées de la boulangerie et du client" do
    expect(text).to include(BakeryDetails::NAME)
    expect(text).to include(BakeryDetails::ADDRESS_LINE)
    expect(text).to include("Épicerie Durand")
    expect(text).to include("epicerie@example.com")
    expect(text).to include("+32470000001")
  end

  it "détaille les pains avec quantité et prix, et le total" do
    expect(text).to include("Pain froment — Petit 600 g")
    expect(text).to include("Pain épeautre — Grand 1 kg")
    expect(text).to include("5,50 €")
    expect(text).to include("16,50 €")
    expect(text).to include("16,00 €")
    expect(text).to match(/Nombre de pains\s+5/)
    expect(text).to match(/Total\s+32,50 €/)
  end

  it "reprend la remarque du client et le cadre de réception" do
    expect(text).to include("Livrer à l'arrière")
    expect(text).to include("REÇU PAR")
    expect(text).to include("Signature")
  end

  it "n'est pas une facture" do
    expect(text).not_to match(/facture/i)
    expect(text).not_to match(/\bTVA\b/)
  end

  context "avec une remise client" do
    let(:total_cents) { 2925 }

    it "expose la remise sur sa propre ligne" do
      expect(text).to include("Total au prix standard")
      expect(text).to include("Remise 10 %")
      expect(text).to include("-3,25 €")
      expect(text).to match(/Total\s+29,25 €/)
    end
  end
end
