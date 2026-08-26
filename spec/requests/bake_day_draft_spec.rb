require "rails_helper"

# #197 — un jour de cuisson en brouillon ne doit jamais atteindre le client, et
# doit rester pleinement exploitable côté admin.
RSpec.describe "Jour de cuisson en brouillon", type: :request do
  let(:tuesday) { Date.current.next_occurring(:tuesday) }
  let(:friday)  { tuesday + 3.days }

  let!(:product) { create(:product, :bread, name: "Pain froment") }
  let!(:variant) { create(:product_variant, product: product, name: "Grand 800 gr", flour_quantity: 800, price_cents: 650) }

  describe "côté boutique" do
    let!(:draft_day) { create(:bake_day, :draft, :can_order, baked_on: tuesday) }

    it "n'est pas annoncé comme prochaine fournée dans le catalogue" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Prochaine fournée")
    end

    it "laisse la place au premier jour NON brouillon" do
      create(:bake_day, :can_order, baked_on: friday)

      get root_path

      expect(response.body).to include("Prochaine fournée")
      expect(response.body).to include(I18n.l(friday, format: "%A %-d %B"))
      expect(response.body).not_to include(I18n.l(tuesday, format: "%A %-d %B"))
    end

    it "n'est pas sélectionnable au checkout" do
      expect(BakeDay.open_to_customers).to be_empty
    end

    it "n'apparaît pas dans le calendrier client" do
      expect(BakeDay.future.visible_to_customers.ordered).to be_empty
    end
  end

  describe "côté admin" do
    before do
      ENV["ADMIN_PASSWORD"] = "test-admin-pw"
      post admin_login_path, params: { password: "test-admin-pw" }
      create(:product_flour, product: product, flour: create(:flour, name: "Froment T65"), percentage: 100)
    end

    let!(:draft_day) { create(:bake_day, :draft, baked_on: tuesday) }

    before do
      order = create(:order, :paid, bake_day: draft_day, total_cents: 3_250)
      create(:order_item, order: order, product_variant: variant, qty: 5, unit_price_cents: 650)
    end

    it "porte le badge « Brouillon » dans la liste des jours de cuisson" do
      get admin_bake_days_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Brouillon")
    end

    it "affiche le badge sur sa page, et rend bien les calculs de panification" do
      get admin_bake_day_path(draft_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Brouillon — hors comptabilité")
      expect(response.body).to include("Panification")
      # 5 × 800 g de pâte : le moteur de calcul tourne normalement.
      expect(response.body).to include("4000 g")
    end

    it "marque clairement la feuille compta comme non comptabilisée, et explique qu'elle est vide" do
      get sheet_admin_bake_day_path(draft_day)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cette feuille n'est PAS comptabilisée.")
      expect(response.body).to include("cette feuille reste vide")
      # Les chiffres du jour ne fuitent nulle part dans la feuille.
      expect(response.body).to include("Aucune donnée pour ce jour.")
    end

    it "propose la case à cocher à la création et à l'édition" do
      get new_admin_bake_day_path
      expect(response.body).to include("bake_day[draft]")

      get edit_admin_bake_day_path(draft_day)
      expect(response.body).to include("bake_day[draft]")
    end

    it "enregistre la bascule brouillon depuis le formulaire" do
      patch admin_bake_day_path(draft_day), params: { bake_day: { draft: "0" } }
      expect(draft_day.reload.draft?).to be false

      patch admin_bake_day_path(draft_day), params: { bake_day: { draft: "1" } }
      expect(draft_day.reload.draft?).to be true
    end
  end

  describe "non-régression" do
    it "un jour NON brouillon se comporte exactement comme avant" do
      real_day = create(:bake_day, :can_order, baked_on: tuesday)

      get root_path

      expect(response.body).to include("Prochaine fournée")
      expect(response.body).to include(I18n.l(tuesday, format: "%A %-d %B"))
      expect(BakeDay.open_to_customers).to contain_exactly(real_day)
      expect(BakeDay.future.visible_to_customers.ordered).to contain_exactly(real_day)
    end
  end
end
