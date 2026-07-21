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

  describe "DELETE /admin/orders/:id" do
    it "deletes an unpaid order and redirects to the index" do
      delete admin_order_path(order)

      expect(Order.exists?(order.id)).to be(false)
      expect(response).to redirect_to(admin_orders_path)
    end

    it "refuses to delete a paid order" do
      paid_order = create(:order, :paid, :payment_paid, :with_items)

      delete admin_order_path(paid_order)

      expect(Order.exists?(paid_order.id)).to be(true)
      expect(response).to redirect_to(admin_order_path(paid_order))
      expect(flash[:alert]).to be_present
    end

    it "refuses to delete an invoiced order" do
      order.update!(invoice_status: :invoiced)

      delete admin_order_path(order)

      expect(Order.exists?(order.id)).to be(true)
      expect(flash[:alert]).to be_present
    end

    it "shows the delete button only for deletable orders" do
      get admin_order_path(order)
      expect(response.body).to include("Supprimer la commande")

      paid_order = create(:order, :paid, :payment_paid, :with_items, bake_day: order.bake_day)
      get admin_order_path(paid_order)
      expect(response.body).not_to include("Supprimer la commande")
    end
  end

  describe "GET /admin/orders (index, #41)" do
    it "displays both a logistic status column and a payment status column" do
      create(:order, :paid, :payment_paid, :with_items)

      get admin_orders_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(">Statut<")
      expect(response.body).to include(">Paiement<")
    end

    it "filters orders by payment status (incl. refunded)" do
      bake_day = create(:bake_day)
      paid_order = create(:order, :paid, :payment_paid, :with_items, bake_day: bake_day)
      refunded_order = create(:order, :cancelled, :payment_refunded, :with_items, bake_day: bake_day)

      get admin_orders_path, params: { payment_status: "refunded" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(refunded_order.order_number)
      expect(response.body).not_to include(paid_order.order_number)
    end
  end

  describe "PATCH /admin/orders/:id (manual payment marking, #41)" do
    it "lets an admin mark an offline order as paid" do
      offline_order = create(:order, :unpaid, :with_items)

      patch admin_order_path(offline_order), params: {
        order: {
          customer_id: offline_order.customer_id,
          bake_day_id: offline_order.bake_day_id,
          status: "unpaid",
          payment_status: "paid",
          final_total_euros: (offline_order.total_cents / 100.0).to_s,
          variant_quantities: offline_order.order_items.each_with_object({}) { |i, h| h[i.product_variant_id] = i.qty }
        }
      }

      expect(offline_order.reload.payment_status).to eq("paid")
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
