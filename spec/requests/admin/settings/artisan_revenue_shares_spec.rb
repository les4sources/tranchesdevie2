require "rails_helper"

# Admin : édition des parts de revenu d'un artisan, historisées par date (#54).
# Sans valeur par défaut : tout est saisi ici.
RSpec.describe "Admin::Settings::ArtisanRevenueShares", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  let(:artisan) { create(:artisan, name: "Claire") }

  it "liste les paliers de part d'un artisan" do
    create(:artisan_revenue_share, artisan: artisan, percent: 100, active_from: Date.new(2026, 1, 1))
    get admin_settings_artisan_revenue_shares_path(artisan)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Claire")
    expect(response.body).to include("100")
  end

  it "crée un palier de part pour l'artisan" do
    expect {
      post admin_settings_artisan_revenue_shares_path(artisan), params: {
        artisan_revenue_share: { percent: "50", active_from: "2026-01-01" }
      }
    }.to change(artisan.artisan_revenue_shares, :count).by(1)

    share = artisan.artisan_revenue_shares.ordered.first
    expect(share.percent).to eq(50)
    expect(response).to redirect_to(admin_settings_artisan_revenue_shares_path(artisan))
  end

  it "met à jour un palier de part" do
    share = create(:artisan_revenue_share, artisan: artisan, percent: 50, active_from: Date.new(2026, 1, 1))

    patch admin_settings_artisan_revenue_share_path(artisan, share), params: {
      artisan_revenue_share: { percent: "100", active_from: "2026-06-01" }
    }

    share.reload
    expect(share.percent).to eq(100)
    expect(share.active_from).to eq(Date.new(2026, 6, 1))
  end

  it "supprime un palier de part" do
    share = create(:artisan_revenue_share, artisan: artisan, percent: 50, active_from: Date.new(2026, 1, 1))
    expect {
      delete admin_settings_artisan_revenue_share_path(artisan, share)
    }.to change(ArtisanRevenueShare, :count).by(-1)
  end

  it "refuse une part sans pourcentage" do
    post admin_settings_artisan_revenue_shares_path(artisan), params: {
      artisan_revenue_share: { percent: "", active_from: "2026-01-01" }
    }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
