require "rails_helper"

# #198 — régulariser un jour de cuisson passé depuis l'admin. Le cas réel :
# Romane rentre du marché, la date est passée, et une partie des ventes doit
# aller sur le compte de Kikrok plutôt que sur un client fourre-tout.
RSpec.describe "Admin::Orders — jour de cuisson passé", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let!(:past_day) { create(:bake_day, baked_on: Date.current.prev_occurring(:tuesday), cut_off_at: 10.days.ago) }

  let(:product) { create(:product, :bread, name: "Pain froment", internal_category: :boulangerie) }
  let!(:variant) { create(:product_variant, product: product, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650) }
  let!(:small) { create(:product_variant, product: product, name: "Petit 600 gr", flour_quantity: 600, price_cents: 400) }

  let(:kikrok) { create(:customer, last_name: "Kikrok", first_name: "Marché") }
  let(:romane) { create(:customer, last_name: "Ancion", first_name: "Romane") }

  let(:pickup) { PickupLocation.default_location }

  def create_order(customer:, quantities:, total_euros:, bake_day: past_day)
    post admin_orders_path, params: {
      order: {
        customer_id: customer.id,
        bake_day_id: bake_day.id,
        status: "paid",
        payment_status: "paid",
        final_total_euros: total_euros,
        variant_quantities: quantities
      }
    }
  end

  describe "le formulaire" do
    it "propose les jours passés dans un groupe « régularisation »" do
      get new_admin_order_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Jours passés — régularisation")
      expect(response.body).to include("À venir").or include("Sélectionner un jour")
    end

    it "libelle les jours en français" do
      get new_admin_order_path

      expect(response.body).to include(I18n.l(past_day.baked_on, format: "%A %d/%m/%Y").capitalize)
      expect(response.body).not_to include(past_day.baked_on.strftime("%A"))
    end

    it "porte l'avertissement et la liste des jours passés, à la création comme à l'édition" do
      create_order(customer: kikrok, quantities: { variant.id.to_s => "4" }, total_euros: "26,00")
      order = Order.last

      [ new_admin_order_path, edit_admin_order_path(order) ].each do |path|
        get path
        expect(response.body).to include("Jour de cuisson passé — régularisation")
        expect(response.body).to include("data-past-bake-day-past-ids-value")
        expect(response.body).to include(past_day.id.to_s)
      end
    end
  end

  describe "créer une commande sur un jour passé" do
    it "crée la commande sans buter sur la date de clôture ni sur la capacité" do
      expect(past_day.cut_off_passed?).to be true

      expect {
        create_order(customer: kikrok, quantities: { variant.id.to_s => "4" }, total_euros: "26,00")
      }.to change(Order, :count).by(1)

      order = Order.last
      expect(response).to redirect_to(admin_order_path(order))
      expect(order.bake_day).to eq(past_day)
      expect(order.customer).to eq(kikrok)
      expect(order.total_cents).to eq(2_600)
      expect(order.order_items.sum(&:qty)).to eq(4)
    end
  end

  describe "modifier les lignes d'une commande sur un jour passé" do
    let!(:order) do
      create_order(customer: kikrok, quantities: { variant.id.to_s => "4" }, total_euros: "26,00")
      Order.last
    end

    it "ajoute une variante, change une quantité et recalcule le total" do
      patch admin_order_path(order), params: {
        order: {
          customer_id: kikrok.id,
          bake_day_id: past_day.id,
          status: "paid",
          payment_status: "paid",
          final_total_euros: "21,00",
          variant_quantities: { variant.id.to_s => "2", small.id.to_s => "2" }
        }
      }

      order.reload
      expect(response).to redirect_to(admin_order_path(order))
      expect(order.total_cents).to eq(2_100)
      expect(order.order_items.pluck(:product_variant_id, :qty).sort)
        .to eq([ [ variant.id, 2 ], [ small.id, 2 ] ].sort)
    end

    it "retire une ligne" do
      patch admin_order_path(order), params: {
        order: {
          customer_id: kikrok.id, bake_day_id: past_day.id,
          status: "paid", payment_status: "paid",
          final_total_euros: "13,00",
          variant_quantities: { variant.id.to_s => "2", small.id.to_s => "0" }
        }
      }

      expect(order.reload.order_items.count).to eq(1)
    end

    it "réaffecte la commande à un autre client — le cas Kikrok / Romane" do
      patch admin_order_path(order), params: {
        order: {
          customer_id: romane.id, bake_day_id: past_day.id,
          status: "paid", payment_status: "paid",
          final_total_euros: "26,00",
          variant_quantities: { variant.id.to_s => "4" }
        }
      }

      expect(order.reload.customer).to eq(romane)
    end
  end

  describe "la remise de groupe" do
    it "s'applique comme sur une commande normale" do
      group = create(:group, discount_percent: 10)
      create(:customer_group, customer: kikrok, group: group)

      get new_admin_order_path(customer_id: kikrok.id)

      expect(response).to have_http_status(:ok)
      # Le calcul temps réel s'appuie sur ces données de remise par client.
      expect(response.body).to include("data-order-calculator-customers-value")
      expect(kikrok.effective_discount_percent).to eq(10)
    end
  end

  describe "propagation en comptabilité" do
    it "fait bouger la feuille compta du jour et les revenus boulangers de la période" do
      create(:variant_cost_price, product_variant: variant, amount_cents: 200, active_from: Date.new(2026, 1, 1))
      artisan = create(:artisan, name: "Romane")
      create(:artisan_revenue_share, artisan: artisan, percent: 100, active_from: Date.new(2026, 1, 1))
      create(:bake_day_artisan, bake_day: past_day, artisan: artisan)

      date = past_day.baked_on
      revenue_before = BakerRevenueService.new(start_date: date, end_date: date).call.total_revenue_cents
      sheet_before = BakeDaySheetService.call(past_day)

      create_order(customer: kikrok, quantities: { variant.id.to_s => "4" }, total_euros: "26,00")

      revenue_after = BakerRevenueService.new(start_date: date, end_date: date).call.total_revenue_cents
      sheet_after = BakeDaySheetService.call(past_day.reload)

      expect(revenue_after - revenue_before).to eq(2_600)
      # 4 unités du Grand 800 gr : la feuille du jour les voit apparaître.
      expect(sheet_after.rows.sum(&:qty) - sheet_before.rows.sum(&:qty)).to eq(4)
      expect(sheet_after.rows.sum(&:sale_cents) - sheet_before.rows.sum(&:sale_cents)).to eq(2_600)
    end
  end

  describe "non-régression côté client" do
    it "un client ne peut toujours pas commander sur un jour passé ou clôturé" do
      expect(past_day.open_to_customers?).to be false
      expect(BakeDay.open_to_customers).not_to include(past_day)
      expect(BakeDayService.can_order_for?(past_day.baked_on)).to be false
    end

    it "les contrôles de capacité restent actifs pour le client sur un jour ouvert" do
      open_day = create(:bake_day, :can_order, baked_on: Date.current.next_occurring(:tuesday))
      mold = create(:mold_type, name: "Petit moule", limit: 2)
      limited = create(:product_variant, product: product, name: "Limité", flour_quantity: 600, mold_type: mold, price_cents: 400)

      result = BakeCapacityService.new(open_day).cart_fits?([ { "product_variant_id" => limited.id, "qty" => 5 } ])

      expect(result[:fits]).to be false
      expect(result[:errors].join).to include("Petit moule")
    end
  end
end
