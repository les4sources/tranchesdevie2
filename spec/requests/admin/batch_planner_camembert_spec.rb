require "rails_helper"

# Pains de Camembert Party dans le tableau des fournées (#camembert-parties) :
# ils sont calculés (1 grand froment pour 5 participants), sans ligne de
# commande, et pourtant leur pâte, leur levain et leurs moules doivent compter
# dans la fournée qui les cuit (signalé par Stéphanie le 13/11/2026).
RSpec.describe "Admin::BatchPlanner — pains de Camembert Party", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:friday) { Date.new(2026, 11, 13) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: friday, cut_off_at: friday - 2.days) }

  let(:flour) { create(:flour, name: "Froment T65") }
  let(:mold_type) { create(:mold_type, name: "Grand moule") }
  let(:froment) { create(:product, :bread, name: "Pain au froment") }
  let!(:grand) { create(:product_variant, product: froment, name: "Grand 1 kg", price_cents: 550, flour_quantity: 1_050, mold_type: mold_type) }

  let(:public_product) { create(:product, :pizza_party_public, category: :dough_balls) }
  let(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, flour_quantity: 250) }

  let!(:event) { create(:party_event, :public_party, held_on: friday, title: "Camembert Party de novembre", menu: :camembert) }
  let!(:batch) { create(:batch, bake_day: bake_day, name: "Fournée 1", position: 1) }

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before do
    create(:product_flour, product: froment, flour: flour, percentage: 100)
    ProductionSetting.current.update!(camembert_bread_variant: grand)
    PartyOrderCreationService.new(
      customer: create(:customer), party_event: event,
      cart_items: [ { "product_variant_id" => adulte.id.to_s, "qty" => "11" } ]
    ).call.update!(status: :paid)
  end

  it "affecte les pains de l'événement à une fournée, qui en porte la pâte et les moules" do
    patch admin_bake_day_batch_assignment_path(bake_day),
          params: { batch_id: batch.id, party_event_id: event.id }, headers: turbo_headers

    expect(response).to have_http_status(:ok)
    expect(event.reload.bread_batch_id).to eq(batch.id)

    entry = Admin::BatchPlanner.new(bake_day).batch_stats.sole
    expect(entry[:units_count]).to eq(3) # 11 participants → 3 pains
    expect(entry[:total_dough_grams]).to be_positive
    expect(entry[:dough][:totals][:levain_kg]).to be_positive
    expect(entry[:molds].sole).to include(mold_type: mold_type, units_count: 3)
  end

  it "les remet en non affectés avec le bouton « — »" do
    event.update!(bread_batch: batch)

    patch admin_bake_day_batch_assignment_path(bake_day),
          params: { batch_id: "", party_event_id: event.id }, headers: turbo_headers

    expect(event.reload.bread_batch_id).to be_nil
    expect(Admin::BatchPlanner.new(bake_day).unassigned_units_count).to eq(3)
  end

  it "les déplace avec toute la variante" do
    patch admin_bake_day_batch_assignment_path(bake_day),
          params: { batch_id: batch.id, product_variant_id: grand.id }, headers: turbo_headers

    expect(event.reload.bread_batch_id).to eq(batch.id)
  end

  it "les range dans une fournée quand on demande une proposition" do
    post admin_bake_day_batch_proposal_path(bake_day), headers: turbo_headers

    expect(response).to have_http_status(:ok)
    expect(event.reload.bread_batch).to be_present
    expect(Admin::BatchPlanner.new(bake_day)).to be_fully_assigned
  end

  it "montre la ligne de l'événement dans l'affectation par client" do
    get admin_bake_day_path(bake_day)

    expect(response.body).to include("Camembert Party de novembre (13/11)")
    expect(response.body).to include("1 pain pour 5 participants")
  end

  it "rend ses pains non affectés quand on supprime la fournée" do
    event.update!(bread_batch: batch)

    delete admin_bake_day_batch_path(bake_day, batch), headers: turbo_headers

    expect(event.reload.bread_batch_id).to be_nil
  end
end
