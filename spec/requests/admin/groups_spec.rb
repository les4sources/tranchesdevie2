require 'rails_helper'

# Admin groups: targeted discounts via nested attributes (#87).
RSpec.describe 'Admin::Groups', type: :request do
  around do |ex|
    original = ENV['ADMIN_PASSWORD']
    ENV['ADMIN_PASSWORD'] = 'test-admin-pw'
    ex.run
    ENV['ADMIN_PASSWORD'] = original
  end

  before { post admin_login_path, params: { password: 'test-admin-pw' } }

  let!(:product) { create(:product) }
  let!(:variant) { create(:product_variant, product: product, price_cents: 700) }

  it 'creates a group with a fixed targeted discount on a variant' do
    expect {
      post admin_groups_path, params: {
        group: {
          name: "Sourciers",
          discount_percent: 50,
          group_product_discounts_attributes: {
            "0" => { target: "variant_#{variant.id}", discount_kind: "fixed", discount_value_raw: "5,00" }
          }
        }
      }
    }.to change(GroupProductDiscount, :count).by(1)

    discount = GroupProductDiscount.last
    expect(discount.product_variant_id).to eq(variant.id)
    expect(discount.discount_kind).to eq("fixed")
    expect(discount.discount_value).to eq(500)
  end

  it 'creates a group with a percent targeted discount on a whole product' do
    post admin_groups_path, params: {
      group: {
        name: "Boulangers",
        discount_percent: 0,
        group_product_discounts_attributes: {
          "0" => { target: "product_#{product.id}", discount_kind: "percent", discount_value_raw: "30" }
        }
      }
    }
    discount = GroupProductDiscount.last
    expect(discount.product_id).to eq(product.id)
    expect(discount.product_variant_id).to be_nil
    expect(discount.discount_value).to eq(30)
  end

  it 'ignores a blank discount row' do
    expect {
      post admin_groups_path, params: {
        group: {
          name: "Sans remise ciblée",
          discount_percent: 10,
          group_product_discounts_attributes: {
            "0" => { target: "", discount_kind: "percent", discount_value_raw: "" }
          }
        }
      }
    }.not_to change(GroupProductDiscount, :count)
    expect(Group.find_by(name: "Sans remise ciblée")).to be_present
  end

  it 'removes a targeted discount via _destroy on update' do
    group = create(:group, discount_percent: 0)
    discount = create(:group_product_discount, :fixed, group: group, product_variant: variant)

    expect {
      patch admin_group_path(group), params: {
        group: {
          name: group.name,
          discount_percent: group.discount_percent,
          group_product_discounts_attributes: {
            "0" => { id: discount.id, _destroy: "1" }
          }
        }
      }
    }.to change(GroupProductDiscount, :count).by(-1)
  end
end
