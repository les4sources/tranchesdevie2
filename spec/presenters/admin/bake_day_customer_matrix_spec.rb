require "rails_helper"

# Retour boulangers : le tableau « Commandes par client » ignorait les pizza
# parties. Les colonnes de leurs variantes existaient déjà (elles viennent de
# `variant_stats`, qui compte les commandes party), mais aucune ligne ne les
# remplissait — les pâtons étaient invisibles et la ligne « Total » ne retombait
# pas sur le tableau global du jour.
RSpec.describe Admin::BakeDayDashboard, "matrice Commandes par client" do
  let(:friday) { Date.new(2026, 9, 4) }

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:friday_bake) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:alice) { create(:customer, first_name: "Alice", last_name: "Aa") }
  let(:bob)   { create(:customer, first_name: "Bob",   last_name: "Bb") }

  let(:pain) { create(:product, :bread, name: "Pain aux graines") }
  let(:petit) { create(:product_variant, product: pain, name: "600 g", price_cents: 550, flour_quantity: 600) }

  let(:private_product) { create(:product, :pizza_party, category: :dough_balls) }
  let(:paton) { create(:product_variant, product: private_product, name: "une boule", price_cents: 500, flour_quantity: 200) }
  let(:public_product) { create(:product, :pizza_party_public, category: :dough_balls) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, flour_quantity: 200) }

  subject(:dashboard) { described_class.new(friday_bake) }

  def book_party(event:, variant:, qty:, customer:)
    PartyOrderCreationService.new(
      customer: customer, party_event: event,
      cart_items: [ { "product_variant_id" => variant.id.to_s, "qty" => qty.to_s } ]
    ).call.tap { |order| order.update!(status: :paid) }
  end

  def row_for(label)
    dashboard.customer_matrix_rows.find { |row| row[:label] == label }
  end

  describe "sans party" do
    let!(:bread_order) do
      create(:order, :paid, customer: alice, bake_day: friday_bake, total_cents: 1_100).tap do |order|
        create(:order_item, order: order, product_variant: petit, qty: 2, unit_price_cents: 550)
      end
    end

    it "ne rend que les lignes clients, comme avant" do
      expect(dashboard.customer_matrix_rows.map { |row| row[:kind] }).to eq([ :customer ])
      expect(row_for("Alice Aa")[:quantities]).to eq(petit.id => 2)
      expect(dashboard.customer_matrix_total_units).to eq(2)
    end
  end

  describe "avec une party privée et une party publique" do
    let!(:bread_order) do
      create(:order, :paid, customer: alice, bake_day: friday_bake, total_cents: 1_100).tap do |order|
        create(:order_item, order: order, product_variant: petit, qty: 2, unit_price_cents: 550)
      end
    end

    let!(:private_event) { create(:party_event, :private_party, held_on: friday, slot: :soir) }
    let!(:public_event)  { create(:party_event, :public_party, held_on: friday, title: "Pizza du vendredi") }

    before do
      # Alice commande AUSSI une party privée : elle garde sa ligne de pain.
      book_party(event: private_event, variant: paton, qty: 11, customer: alice)
      book_party(event: public_event, variant: adulte, qty: 5, customer: alice)
      book_party(event: public_event, variant: adulte, qty: 3, customer: bob)
    end

    it "ajoute une ligne par party privée, au nom de son client, sans toucher à sa ligne de pain" do
      bread_row = row_for("Alice Aa")
      party_row = dashboard.customer_matrix_rows.find { |row| row[:kind] == :private_party }

      expect(bread_row[:kind]).to eq(:customer)
      expect(bread_row[:quantities]).to eq(petit.id => 2)

      expect(party_row[:label]).to eq("Alice Aa")
      expect(party_row[:party_event]).to eq(private_event)
      expect(party_row[:slot_label]).to eq("Soir")
      expect(party_row[:quantities][paton.id]).to eq(11)
    end

    it "agrège la party PUBLIQUE en une seule ligne, quelles que soient ses inscriptions" do
      public_rows = dashboard.customer_matrix_rows.select { |row| row[:kind] == :public_party }

      expect(public_rows.size).to eq(1)
      expect(public_rows.first[:label]).to eq("Pizza du vendredi")
      expect(public_rows.first[:orders_count]).to eq(2)
      expect(public_rows.first[:quantities][adulte.id]).to eq(8)
    end

    it "range les lignes party APRÈS les clients de pain" do
      kinds = dashboard.customer_matrix_rows.map { |row| row[:kind] }

      expect(kinds.first).to eq(:customer)
      expect(kinds.drop(1)).to all(satisfy { |kind| %i[private_party public_party].include?(kind) })
    end

    it "compte les parties dans les totaux de colonnes et dans le total général" do
      expect(dashboard.customer_matrix_column_totals[petit.id]).to eq(2)
      expect(dashboard.customer_matrix_column_totals[paton.id]).to eq(11)
      expect(dashboard.customer_matrix_column_totals[adulte.id]).to eq(8)
    end

    # L'invariant qui manquait : la matrice et le tableau global des articles
    # regardent désormais exactement la même assiette de lignes de commande.
    it "retombe sur les mêmes unités que le tableau « Articles & variantes »" do
      expect(dashboard.customer_matrix_total_units).to eq(dashboard.variant_stats.sum { |stat| stat[:units_count] })
      expect(dashboard.customer_matrix_total_units).to eq(dashboard.kpis[:items_count])

      dashboard.variant_stats.each do |stat|
        expect(dashboard.customer_matrix_column_totals[stat[:variant].id]).to eq(stat[:units_count])
      end
    end
  end
end
