require "rails_helper"

# Camembert Party (#camembert-parties) : les convives cuisent leur fromage, la
# boulangerie ne pétrit AUCUN pâton mais fournit un grand froment 1 kg pour
# cinq personnes (adultes et enfants confondus), arrondi au pain supérieur.
RSpec.describe Admin::BakeDayDashboard, "Camembert Party" do
  let(:friday) { Date.new(2026, 11, 13) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:friday_bake) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:froment) { create(:product, :bread, name: "Pain au froment") }
  let(:grand) { create(:product_variant, product: froment, name: "Grand 1 kg", price_cents: 550, flour_quantity: 1_050) }

  let(:public_product) { create(:product, :pizza_party_public, category: :dough_balls) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, flour_quantity: 250) }
  let(:enfant) { create(:product_variant, product: public_product, name: "enfant", price_cents: 600, flour_quantity: 250) }

  let!(:event) { create(:party_event, :public_party, held_on: friday, title: "Camembert Party de novembre", menu: :camembert) }

  subject(:dashboard) { described_class.new(friday_bake) }

  before { ProductionSetting.current.update!(camembert_bread_variant: grand) }

  def register(variant:, qty:)
    PartyOrderCreationService.new(
      customer: create(:customer), party_event: event,
      cart_items: [ { "product_variant_id" => variant.id.to_s, "qty" => qty.to_s } ]
    ).call.tap { |order| order.update!(status: :paid) }
  end

  it "compte 1 pain pour 5 participants, arrondi au-dessus, sur l'événement entier" do
    register(variant: adulte, qty: 4)
    register(variant: enfant, qty: 3)
    register(variant: adulte, qty: 4) # 11 participants → 3 pains

    entry = dashboard.camembert_breads.sole
    expect(entry[:persons]).to eq(11)
    expect(entry[:bread_count]).to eq(3)
  end

  it "remplace les places par les pains dans les quantités, la matrice et la pâte" do
    register(variant: adulte, qty: 10)

    variant_ids = dashboard.variant_stats.map { |stat| stat[:variant].id }
    expect(variant_ids).to include(grand.id)
    expect(variant_ids).not_to include(adulte.id)
    expect(dashboard.variant_stats.find { |stat| stat[:variant] == grand }[:units_count]).to eq(2)

    row = dashboard.customer_matrix_rows.find { |r| r[:kind] == :public_party }
    expect(row[:quantities]).to eq(grand.id => 2)

    # 2 pains de 1 050 g, aucun pâton de 250 g.
    expect(dashboard.total_flour_quantity).to eq(2_100)
  end

  it "annonce des pains, pas des pâtons, sur la card de la party" do
    register(variant: adulte, qty: 6)

    card = dashboard.party_preparation_cards.sole
    expect(card[:bread_only]).to be(true)
    expect(card[:kind_label]).to eq("Camembert Party")
    expect(card[:camembert][:bread_count]).to eq(2)
  end

  it "ne propose pas les pains calculés au planificateur de fournées" do
    register(variant: adulte, qty: 6)

    expect(dashboard.production_items).to all(be_persisted)
  end

  it "laisse une Pizza Party publique en pâtons" do
    event.update!(menu: :pizza)
    register(variant: adulte, qty: 6)

    expect(dashboard.camembert_breads).to be_empty
    expect(dashboard.variant_stats.map { |stat| stat[:variant].id }).to include(adulte.id)
  end
end

RSpec.describe PartyEvent, ".camembert_bread_count" do
  it { expect(described_class.camembert_bread_count(0)).to eq(0) }
  it { expect(described_class.camembert_bread_count(1)).to eq(1) }
  it { expect(described_class.camembert_bread_count(5)).to eq(1) }
  it { expect(described_class.camembert_bread_count(6)).to eq(2) }
  it { expect(described_class.camembert_bread_count(66)).to eq(14) }
end

RSpec.describe BakeCapacityService, "pains des Camembert Parties" do
  let(:friday) { Date.new(2026, 11, 13) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }
  let(:grand_mold) { create(:mold_type, name: "Grand", limit: 95) }
  let(:froment) { create(:product, :bread, name: "Pain au froment") }
  let(:grand) { create(:product_variant, product: froment, name: "Grand 1 kg", price_cents: 550, flour_quantity: 1_050, mold_type: grand_mold) }
  let(:public_product) { create(:product, :pizza_party_public, category: :dough_balls) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, flour_quantity: 250) }
  let!(:event) { create(:party_event, :public_party, held_on: friday, title: "Camembert Party", menu: :camembert) }

  before do
    ProductionSetting.current.update!(camembert_bread_variant: grand)
    PartyOrderCreationService.new(
      customer: create(:customer), party_event: event,
      cart_items: [ { "product_variant_id" => adulte.id.to_s, "qty" => "11" } ]
    ).call.update!(status: :paid)
  end

  it "compte les pains dans les moules et dans le four" do
    usage = described_class.new(bake_day).usage

    expect(usage[:molds].find { |entry| entry[:mold_type] == grand_mold }[:used]).to eq(3)
    expect(usage[:oven][:used]).to eq(3 * 1_050)
  end
end
