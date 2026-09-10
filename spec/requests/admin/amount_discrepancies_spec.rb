require "rails_helper"
require "pdf/reader"

# Écran + PDF des écarts de montant (#retour Manon) : la liste des commandes dont
# le total ne se déduit pas de leur détail, pour que la compta fasse le point.
RSpec.describe "Admin::AmountDiscrepancies", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  def login_admin
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  it "exige une authentification" do
    get admin_amount_discrepancies_path
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before { login_admin }

    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:variant) { create(:product_variant, price_cents: 450) }
    let!(:divergent) do
      create(:customer, first_name: "Épicerie", last_name: "Durand").then do |customer|
        create(:order, customer: customer, bake_day: bake_day, status: :unpaid,
                       source: :admin, total_cents: 9000).tap do |order|
          create(:order_item, order: order, product_variant: variant, qty: 18, unit_price_cents: 450)
        end
      end
    end

    it "liste la commande divergente avec sa somme de lignes et son écart" do
      get admin_amount_discrepancies_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(divergent.order_number)
      expect(response.body).to include("Épicerie Durand")
      expect(response.body).to include("81,00")  # somme des lignes
      expect(response.body).to include("90,00")  # montant enregistré
    end

    it "propose un lien vers le formulaire de correction de la commande" do
      get admin_amount_discrepancies_path

      expect(response.body).to include(edit_admin_order_path(divergent))
    end

    it "annonce le nombre de commandes analysées et d'écarts couverts par une remise" do
      get admin_amount_discrepancies_path

      expect(response.body).to include("Commandes analysées")
      expect(response.body).to include("Couverts par une remise de groupe")
    end

    it "sert le PDF de la liste" do
      get admin_amount_discrepancies_path(format: :pdf)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("ecarts-de-montant-")

      text = PDF::Reader.new(StringIO.new(response.body)).pages.map(&:text).join("\n")
      expect(text).to include("Écarts de montant")
      expect(text).to include(divergent.order_number)
      expect(text).to include("81,00 €")
      expect(text).to include("90,00 €")
      expect(text).to include("+9,00 €")
    end

    it "dit clairement qu'il n'y a rien à relire quand tout est cohérent" do
      divergent.update!(total_cents: 8100)

      get admin_amount_discrepancies_path

      expect(response.body).to include("Aucun écart à relire")
    end

    it "est accessible depuis l'écran Facturation" do
      get admin_billing_path

      expect(response.body).to include(admin_amount_discrepancies_path)
      expect(response.body).to include("Écarts de montant")
    end
  end
end
