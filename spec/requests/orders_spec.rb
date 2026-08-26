require 'rails_helper'

# ISC-23: a customer can view their order via its public token, no login required.
RSpec.describe 'Public order page', type: :request do
  it 'shows an order by its public token without authentication' do
    order = create(:order, :with_items)
    get order_path(order.public_token)
    expect(response).to have_http_status(:ok)
  end
end
