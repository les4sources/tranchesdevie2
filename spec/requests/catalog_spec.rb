require 'rails_helper'

# ISC-86: le catalogue n'affiche une variante restreinte que les jours correspondants.
RSpec.describe 'Catalog', type: :request do
  let!(:product) { create(:product, category: :breads, channel: 'store') }
  let!(:always) { create(:product_variant, product: product, channel: 'store', name: 'Pain toujours') }
  let!(:friday_only) { create(:product_variant, :friday_only, product: product, channel: 'store', name: 'Pain du vendredi') }

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
