require "rails_helper"

RSpec.describe "Admin::Reports customer_origins", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  it "affiche les villages des acheteurs de la période" do
    bake_day = create(:bake_day)
    create(:order, :paid, customer: create(:customer, locality: "Durnal"), bake_day: bake_day)
    create(:order, :paid, customer: create(:customer, locality: nil), bake_day: bake_day)

    get customer_origins_admin_reports_path(start_date: bake_day.baked_on - 1, end_date: bake_day.baked_on + 1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Durnal")
    expect(response.body).to include("Non renseigné")
    expect(response.body).to include("50 %")
  end

  it "recharge la même page quand on change la période" do
    get customer_origins_admin_reports_path

    expect(response.body).to include(%(action="#{customer_origins_admin_reports_path}"))
  end

  it "laisse l'admin renseigner le village d'un mangeur" do
    customer = create(:customer)

    patch admin_customer_path(customer), params: { customer: { first_name: customer.first_name, locality: "purnode" } }

    expect(customer.reload.locality).to eq("Purnode")
  end
end
