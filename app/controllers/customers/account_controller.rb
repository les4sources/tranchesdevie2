class Customers::AccountController < ApplicationController
  before_action :authenticate_customer!

  def show
    @customer = current_customer
    @orders = @customer.orders
                      .includes(:bake_day, :order_items => { product_variant: :product })
                      .order('bake_days.baked_on DESC')
  end

  def edit
    @customer = current_customer
  end

  def update
    @customer = current_customer

    if @customer.update(customer_params)
      redirect_to customers_account_path, notice: 'Profil mis à jour avec succès'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def cancel_order
    @order = current_customer.orders.find_by(id: params[:id])

    unless @order
      redirect_to customers_account_path, alert: 'Commande introuvable'
      return
    end

    unless @order.can_be_cancelled_by_customer?
      redirect_to customers_account_path, alert: 'Cette commande ne peut pas être annulée'
      return
    end

    @order.destroy
    redirect_to customers_account_path, notice: 'Commande annulée avec succès'
  end

  private

  def customer_params
    params.require(:customer).permit(:first_name, :last_name, :phone_e164, :email, :sms_opt_out)
  end
end

