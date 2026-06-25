require 'rails_helper'

RSpec.describe "Admin::Orders", type: :request do
  let(:order) { create(:order, :unpaid, :with_items) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('ADMIN_PASSWORD').and_return('secret')
    post admin_login_path, params: { password: 'secret' }
  end

  describe "PATCH /admin/orders/:id/update_status (marquer payée)" do
    it "transitions the order to paid and stores the supplied payment date" do
      patch update_status_admin_order_path(order),
            params: { status: 'paid', paid_at: '2026-05-12' }

      order.reload
      expect(order.status).to eq('paid')
      expect(order.read_attribute(:paid_at)).to eq(Time.zone.local(2026, 5, 12))
    end

    it "defaults the payment date to now when none is supplied" do
      patch update_status_admin_order_path(order), params: { status: 'paid' }

      expect(order.reload.read_attribute(:paid_at)).to be_within(1.minute).of(Time.current)
    end

    it "does not set a payment date for other transitions" do
      paid_order = create(:order, :paid, :with_items)

      patch update_status_admin_order_path(paid_order), params: { status: 'ready' }

      expect(paid_order.reload.read_attribute(:paid_at)).to be_nil
    end
  end

  describe "GET /admin/orders/:id (show)" do
    it "displays the manually recorded payment date for an offline payment" do
      order.update!(status: :paid, paid_at: Time.zone.local(2026, 5, 12))

      get admin_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Payé le 12/05/2026")
    end
  end

  describe "GET /admin/orders (index, group name #99)" do
    it "shows the group name as primary with the customer name below it" do
      customer = create(:customer, first_name: "Joséphine", last_name: "Martin")
      create(:order, :unpaid, :with_items, customer: customer, group_name: "Entreprise X")

      get admin_orders_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Entreprise X")
      expect(response.body).to include("Joséphine Martin")
    end

    it "shows only the customer name when no group is set" do
      customer = create(:customer, first_name: "Paul", last_name: "Durand")
      create(:order, :unpaid, :with_items, customer: customer)

      get admin_orders_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Paul Durand")
    end
  end
end
