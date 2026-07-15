require "rails_helper"
require "pdf/reader"

# Feuille d'émargement d'un point de retrait (#148) : une ligne par client, avec
# une case à cocher AU STYLO. Aucun pointage en ligne, aucun changement de statut.
RSpec.describe PickupSheetPdfService, type: :service do
  let!(:default_location) { create(:pickup_location, :default) }
  let(:anhee) { create(:pickup_location, name: "Marché d'Anhée", description: "Sur notre étal, place d'Anhée.") }
  let(:bake_day) { create(:bake_day, :can_order, baked_on: Date.new(2026, 8, 4)) }

  let(:product) { create(:product, name: "Pain froment") }
  let(:variant) { create(:product_variant, product: product, name: "Grand 1 kg", price_cents: 700) }

  before do
    bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
    bake_day.save!
  end

  def pdf_text(binary)
    PDF::Reader.new(StringIO.new(binary)).pages.map(&:text).join("\n")
  end

  def order_for(customer, location, qty: 2)
    create(:order, customer: customer, bake_day: bake_day, pickup_location: location, total_cents: qty * 700).tap do |order|
      create(:order_item, order: order, product_variant: variant, qty: qty, unit_price_cents: 700)
    end
  end

  let(:zoe) { create(:customer, first_name: "Zoé", last_name: "Zimmer", phone_e164: "+32470000003") }
  let(:alice) { create(:customer, first_name: "Alice", last_name: "Adam", phone_e164: "+32470000001") }
  let(:bruno) { create(:customer, first_name: "Bruno", last_name: "Bernard", phone_e164: "+32470000002") }

  subject(:service) { described_class.new(bake_day, anhee) }

  it "porte en en-tête le nom du lieu, sa description et la date de la fournée" do
    order_for(alice, anhee)

    text = pdf_text(service.render)

    expect(text).to include("Marché d'Anhée")
    expect(text).to include("Sur notre étal, place d'Anhée.")
    expect(text).to include(I18n.l(bake_day.baked_on))
  end

  it "liste les clients du lieu avec téléphone, détail et total" do
    order_for(alice, anhee, qty: 2)

    text = pdf_text(service.render)

    expect(text).to include("Alice Adam")
    expect(text).to include("+32470000001")
    expect(text).to include("2 × Pain froment (Grand 1 kg)")
    expect(text).to include("14,00 €")
  end

  it "trie les lignes par nom de client" do
    order_for(zoe, anhee)
    order_for(alice, anhee)
    order_for(bruno, anhee)

    text = pdf_text(service.render)

    expect(text.index("Alice Adam")).to be < text.index("Bruno Bernard")
    expect(text.index("Bruno Bernard")).to be < text.index("Zoé Zimmer")
  end

  it "ne contient QUE les commandes de ce lieu pour cette fournée" do
    order_for(alice, anhee)
    order_for(bruno, default_location) # autre lieu, même fournée

    other_bake_day = create(:bake_day, :friday)
    create(:order, customer: zoe, bake_day: other_bake_day, pickup_location: default_location)

    text = pdf_text(service.render)

    expect(text).to include("Alice Adam")
    expect(text).not_to include("Bruno Bernard")
    expect(text).not_to include("Zoé Zimmer")
  end

  it "exclut les commandes annulées (mêmes statuts que le tableau de bord)" do
    order_for(alice, anhee)
    create(:order, :cancelled, customer: bruno, bake_day: bake_day, pickup_location: anhee)

    text = pdf_text(service.render)

    expect(text).to include("Alice Adam")
    expect(text).not_to include("Bruno Bernard")
  end

  it "produit un PDF lisible même sans aucune commande" do
    text = pdf_text(service.render)

    expect(text).to include("Marché d'Anhée")
    expect(text).to include("Aucune commande à retirer")
  end

  it "propose un nom de fichier parlant" do
    expect(service.filename).to eq("retrait-marche-d-anhee-2026-08-04.pdf")
  end
end
