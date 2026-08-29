require "rails_helper"

# #194 — le calculateur de fournées côté requêtes : création / renommage /
# suppression d'une fournée, et les trois portées d'affectation (une ligne, tout
# un client, toute une variante). Rien ici ne doit toucher la comptabilité.
RSpec.describe "Admin::BatchPlanner", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:bake_day) { create(:bake_day) }
  let(:flour) { create(:flour, name: "Froment T65") }
  let(:mold_type) { create(:mold_type, name: "Grand moule") }
  let(:product) { create(:product, :bread, name: "Pain froment") }

  before { create(:product_flour, product: product, flour: flour, percentage: 100) }

  let(:big)   { create(:product_variant, product: product, name: "Grand 800 gr", flour_quantity: 800, mold_type: mold_type, price_cents: 550) }
  let(:small) { create(:product_variant, product: product, name: "Petit 600 gr", flour_quantity: 600, mold_type: mold_type, price_cents: 400) }

  let(:alice) { create(:customer, first_name: "Alice", last_name: "Aa") }
  let(:bob)   { create(:customer, first_name: "Bob",   last_name: "Bb") }

  let!(:alice_order) { create(:order, :paid, customer: alice, bake_day: bake_day, total_cents: 1_500) }
  let!(:bob_order)   { create(:order, :paid, customer: bob,   bake_day: bake_day, total_cents: 800) }

  let!(:alice_big)   { create(:order_item, order: alice_order, product_variant: big,   qty: 2, unit_price_cents: 550) }
  let!(:alice_small) { create(:order_item, order: alice_order, product_variant: small, qty: 1, unit_price_cents: 400) }
  let!(:bob_small)   { create(:order_item, order: bob_order,   product_variant: small, qty: 2, unit_price_cents: 400) }

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

  describe "l'onglet Fournées sur la page du jour" do
    it "s'affiche à côté des onglets existants" do
      get admin_bake_day_path(bake_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-panel="batches"')
      expect(response.body).to include("Calculateur de fournées")
    end
  end

  describe "POST create" do
    it "crée une fournée nommée par défaut et renvoie le planificateur" do
      expect {
        post admin_bake_day_batches_path(bake_day), headers: turbo_headers
      }.to change { bake_day.batches.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(bake_day.batches.ordered.last.name).to eq("Fournée 1")
      expect(response.body).to include("batch-planner")
    end
  end

  describe "PATCH update" do
    let!(:batch) { create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1) }

    it "renomme la fournée" do
      patch admin_bake_day_batch_path(bake_day, batch), params: { batch: { name: "Les froments" } }, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(batch.reload.name).to eq("Les froments")
    end
  end

  describe "DELETE destroy" do
    let!(:batch) { create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1) }

    before { alice_big.update!(batch: batch) }

    it "supprime la fournée sans perdre la ligne" do
      expect {
        delete admin_bake_day_batch_path(bake_day, batch), headers: turbo_headers
      }.not_to change(OrderItem, :count)

      expect(response).to have_http_status(:ok)
      expect(alice_big.reload.batch_id).to be_nil
    end
  end

  describe "PATCH batch_assignment" do
    let!(:first)  { create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1) }
    let!(:second) { create(:batch, bake_day: bake_day, name: "Fournée 2", position: 2) }

    def assign(params)
      patch admin_bake_day_batch_assignment_path(bake_day), params: params, headers: turbo_headers
    end

    it "affecte une ligne unique" do
      assign(batch_id: first.id, order_item_id: alice_big.id)

      expect(response).to have_http_status(:ok)
      expect(alice_big.reload.batch_id).to eq(first.id)
      expect(alice_small.reload.batch_id).to be_nil
    end

    it "affecte tout un client en une action" do
      assign(batch_id: first.id, customer_id: alice.id)

      expect(alice_big.reload.batch_id).to eq(first.id)
      expect(alice_small.reload.batch_id).to eq(first.id)
      expect(bob_small.reload.batch_id).to be_nil
    end

    it "affecte toutes les lignes d'une même variante en une action" do
      assign(batch_id: second.id, product_variant_id: small.id)

      expect(alice_small.reload.batch_id).to eq(second.id)
      expect(bob_small.reload.batch_id).to eq(second.id)
      expect(alice_big.reload.batch_id).to be_nil
    end

    it "combine les deux sélections : une variante entière puis le retrait d'un client" do
      assign(batch_id: second.id, product_variant_id: small.id)
      assign(batch_id: "", customer_id: bob.id)

      expect(alice_small.reload.batch_id).to eq(second.id)
      expect(bob_small.reload.batch_id).to be_nil
    end

    it "désaffecte quand batch_id est vide" do
      assign(batch_id: first.id, order_item_id: alice_big.id)
      assign(batch_id: "", order_item_id: alice_big.id)

      expect(alice_big.reload.batch_id).to be_nil
    end

    it "persiste la répartition et la recharge à l'identique" do
      assign(batch_id: first.id, customer_id: alice.id)
      assign(batch_id: second.id, customer_id: bob.id)

      get admin_bake_day_path(bake_day)

      planner = Admin::BatchPlanner.new(bake_day.reload)
      expect(planner.batch_stats.map { |entry| entry[:total_dough_grams] }).to eq([ 2_200, 1_200 ])
      expect(planner).to be_fully_assigned
    end

    it "refuse d'affecter la ligne d'un autre jour de cuisson" do
      other_day = create(:bake_day, baked_on: bake_day.baked_on + 3.days)
      other_order = create(:order, :paid, customer: alice, bake_day: other_day, total_cents: 550)
      other_item = create(:order_item, order: other_order, product_variant: big, qty: 1, unit_price_cents: 550)

      assign(batch_id: first.id, order_item_id: other_item.id)

      expect(other_item.reload.batch_id).to be_nil
    end

    it "ignore une portée absente plutôt que d'affecter tout le jour" do
      assign(batch_id: first.id)

      expect(response).to have_http_status(:ok)
      expect(OrderItem.where.not(batch_id: nil)).to be_empty
    end
  end

  # Non-régression compta : la répartition en fournées est purement
  # organisationnelle. Les revenus boulangers et la feuille compta doivent
  # produire EXACTEMENT le même résultat avant et après.
  describe "aucun effet sur la comptabilité" do
    let!(:batch) { create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1) }

    it "laisse la feuille compta et les revenus boulangers inchangés" do
      sheet_before = BakeDaySheetService.call(bake_day)
      revenue_before = BakerRevenueService.new(start_date: bake_day.baked_on, end_date: bake_day.baked_on).call

      patch admin_bake_day_batch_assignment_path(bake_day),
            params: { batch_id: batch.id, customer_id: alice.id }, headers: turbo_headers
      patch admin_bake_day_batch_assignment_path(bake_day),
            params: { batch_id: batch.id, customer_id: bob.id }, headers: turbo_headers

      sheet_after = BakeDaySheetService.call(bake_day.reload)
      revenue_after = BakerRevenueService.new(start_date: bake_day.baked_on, end_date: bake_day.baked_on).call

      expect(sheet_after).to eq(sheet_before)
      expect(revenue_after).to eq(revenue_before)
    end
  end
end
