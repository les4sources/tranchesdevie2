require "rails_helper"

# Admin : édition des paramètres généraux historisés du calcul des revenus
# boulangers (#54) — transport (€) et taux 4 Sources (%). Les unités saisies
# sont converties vers l'entier stocké (cents / points de base).
RSpec.describe "Admin::Settings::RevenueParameters", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  it "liste les paramètres et leurs paliers" do
    create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
    get admin_settings_revenue_parameters_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Transport")
    expect(response.body).to include("Taux")
  end

  it "crée un palier transport en convertissant les euros en cents" do
    expect {
      post admin_settings_revenue_parameters_path, params: {
        revenue_parameter: { key: RevenueParameter::TRANSPORT, value_input: "15", active_from: "2026-01-01" }
      }
    }.to change(RevenueParameter, :count).by(1)

    param = RevenueParameter.for_key(RevenueParameter::TRANSPORT).last
    expect(param.value).to eq(1_500) # 15 € → 1500 cents
    expect(response).to redirect_to(admin_settings_revenue_parameters_path)
  end

  it "crée un palier taux 4 Sources en convertissant le pourcentage en points de base" do
    post admin_settings_revenue_parameters_path, params: {
      revenue_parameter: { key: RevenueParameter::FOUR_SOURCES_RATE, value_input: "30", active_from: "2026-01-01" }
    }

    param = RevenueParameter.for_key(RevenueParameter::FOUR_SOURCES_RATE).last
    expect(param.value).to eq(3_000) # 30 % → 3000 points de base
  end

  it "met à jour un palier existant" do
    param = create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))

    patch admin_settings_revenue_parameter_path(param), params: {
      revenue_parameter: { value_input: "18", active_from: "2026-04-01" }
    }

    param.reload
    expect(param.value).to eq(1_800) # 18 € → 1800 cents
    expect(param.active_from).to eq(Date.new(2026, 4, 1))
  end

  it "supprime un palier" do
    param = create(:revenue_parameter, :transport, value: 1_500, active_from: Date.new(2026, 1, 1))
    expect {
      delete admin_settings_revenue_parameter_path(param)
    }.to change(RevenueParameter, :count).by(-1)
  end
end
