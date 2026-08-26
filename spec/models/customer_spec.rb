require 'rails_helper'

RSpec.describe Customer, type: :model do
  it 'can be destroyed without raising' do
    customer = create(:customer)

    expect { customer.destroy }.not_to raise_error
    expect(customer).to be_destroyed
  end
end
