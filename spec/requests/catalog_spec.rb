require 'rails_helper'

# ISC-86: le catalogue n'affiche une variante restreinte que les jours correspondants.
RSpec.describe 'Catalog', type: :request do
  let!(:product) { create(:product, category: :breads, channel: 'store') }
  let!(:always) { create(:product_variant, product: product, channel: 'store', name: 'Pain toujours') }
  let!(:friday_only) { create(:product_variant, :friday_only, product: product, channel: 'store', name: 'Pain du vendredi') }

  # Régression : le bandeau « Prochaine fournée » se calculait sans filtrer les
  # jours de cuisson ordinaires, et annonçait donc aux clients une fournée
  # réservée aux boulangers (marché) sur laquelle ils ne peuvent pas commander.
  describe 'bandeau « Prochaine fournée »' do
    it "annonce la prochaine fournée ordinaire" do
      tuesday = create(:bake_day, :tuesday, cut_off_at: 2.days.from_now)

      get catalog_path

      expect(response.body).to include(I18n.l(tuesday.baked_on, format: "%A %-d %B"))
    end

    it "n'annonce pas une fournée réservée aux boulangers, même plus proche" do
      # La veille du mardi (un lundi, hors cuisson) est toujours avant lui — un
      # « samedi prochain » ne l'est pas du samedi au lundi.
      marche = create(:bake_day, baked_on: Date.current.next_occurring(:tuesday).prev_day, cut_off_at: 6.hours.from_now)
      tuesday = create(:bake_day, :tuesday, cut_off_at: 2.days.from_now)
      expect(marche.baked_on).to be < tuesday.baked_on

      get catalog_path

      expect(response.body).not_to include(I18n.l(marche.baked_on, format: "%A %-d %B"))
      expect(response.body).to include(I18n.l(tuesday.baked_on, format: "%A %-d %B"))
    end
  end

  it 'shows every variant when no bake day is selected' do
    get catalog_path
    expect(response.body).to include('Pain toujours')
    expect(response.body).to include('Pain du vendredi')
  end

  it 'hides a friday-only variant when a tuesday bake day is selected' do
    tuesday = create(:bake_day, :tuesday, cut_off_at: 2.days.from_now)
    patch cart_update_bake_day_path, params: { bake_day_id: tuesday.id }, as: :json
    expect(session[:bake_day_id]).to eq(tuesday.id)

    get catalog_path
    expect(response.body).to include('Pain toujours')
    expect(response.body).not_to include('Pain du vendredi')
  end

  it 'shows a friday-only variant when a friday bake day is selected' do
    friday = create(:bake_day, :friday, cut_off_at: 2.days.from_now)
    patch cart_update_bake_day_path, params: { bake_day_id: friday.id }, as: :json

    get catalog_path
    expect(response.body).to include('Pain du vendredi')
  end
end
