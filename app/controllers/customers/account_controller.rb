class Customers::AccountController < ApplicationController
  before_action :authenticate_customer!

  def show
    @customer = current_customer
    @orders = @customer.orders
                      .visible_to_customer
                      .includes(:bake_day, order_items: { product_variant: :product })
                      .order("bake_days.baked_on DESC")
                      .to_a
    @member_since = @customer.created_at
    @orders_count = @orders.size
    @ready_count = @orders.count { |o| o.status == "ready" }
    @total_spent_cents = @orders.reject { |o| o.status == "cancelled" }.sum(&:total_cents)
  end

  def edit
    @customer = current_customer
  end

  def update
    @customer = current_customer

    if @customer.update(customer_params)
      redirect_to customers_account_path, notice: "Profil mis à jour avec succès"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def cancel_order
    @order = current_customer.orders.find_by(id: params[:id])

    unless @order
      redirect_to customers_account_path, alert: "Commande introuvable"
      return
    end

    unless @order.can_be_cancelled_by_customer?
      redirect_to customers_account_path, alert: "Cette commande ne peut pas être annulée"
      return
    end

    @order.destroy
    redirect_to customers_account_path, notice: "Commande annulée avec succès"
  end

  def pickup_order
    @order = current_customer.orders.find_by(id: params[:id])

    unless @order
      redirect_to customers_account_path, alert: "Commande introuvable"
      return
    end

    unless @order.can_be_picked_up_by_customer?
      redirect_to customers_account_path, alert: "Cette commande ne peut pas être marquée comme récupérée"
      return
    end

    @order.transition_to!(:picked_up)
    redirect_to customers_account_path, notice: "Commande marquée comme récupérée. Bon appétit !"
  end

  private

  def customer_params
    params.require(:customer).permit(:first_name, :last_name, :phone_e164, :email, :sms_opt_out, :email_opt_out)
  end
end
