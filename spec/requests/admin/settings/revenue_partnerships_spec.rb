require "rails_helper"

# Admin : gestion des partenariats de revenu boulangers (#54). Un partenariat
# regroupe des artisans qui mettent en commun leur revenu puis se le partagent
# à parts égales.
RSpec.describe "Admin::Settings::RevenuePartnerships", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  let!(:romane) { create(:artisan, name: "Romane") }
  let!(:stephanie) { create(:artisan, name: "Stéphanie") }

  it "liste les partenariats avec leurs membres" do
    partnership = create(:revenue_partnership, name: "Romane & Stéphanie")
    create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: romane)
    create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: stephanie)

    get admin_settings_revenue_partnerships_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Romane &amp; Stéphanie")
    expect(response.body).to include("Romane", "Stéphanie")
  end

  it "crée un partenariat avec ses membres" do
    expect {
      post admin_settings_revenue_partnerships_path, params: {
        revenue_partnership: { name: "Romane & Stéphanie", active: "1", artisan_ids: [ romane.id, stephanie.id ] }
      }
    }.to change(RevenuePartnership, :count).by(1)

    partnership = RevenuePartnership.order(:created_at).last
    expect(partnership.name).to eq("Romane & Stéphanie")
    expect(partnership.artisans).to match_array([ romane, stephanie ])
    expect(response).to redirect_to(admin_settings_revenue_partnerships_path)
  end

  it "met à jour la composition d'un partenariat" do
    partnership = create(:revenue_partnership, name: "Duo")
    create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: romane)

    patch admin_settings_revenue_partnership_path(partnership), params: {
      revenue_partnership: { name: "Duo", active: "1", artisan_ids: [ romane.id, stephanie.id ] }
    }

    expect(partnership.reload.artisans).to match_array([ romane, stephanie ])
    expect(response).to redirect_to(admin_settings_revenue_partnerships_path)
  end

  it "retire un membre quand il est décoché" do
    partnership = create(:revenue_partnership, name: "Duo")
    create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: romane)
    create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: stephanie)

    patch admin_settings_revenue_partnership_path(partnership), params: {
      revenue_partnership: { name: "Duo", active: "1", artisan_ids: [ romane.id ] }
    }

    expect(partnership.reload.artisans).to match_array([ romane ])
  end

  it "supprime un partenariat sans supprimer les artisans" do
    partnership = create(:revenue_partnership, name: "Duo")
    create(:revenue_partnership_membership, revenue_partnership: partnership, artisan: romane)

    expect {
      delete admin_settings_revenue_partnership_path(partnership)
    }.to change(RevenuePartnership, :count).by(-1)

    expect(Artisan.exists?(romane.id)).to be(true)
    expect(response).to redirect_to(admin_settings_revenue_partnerships_path)
  end
end
