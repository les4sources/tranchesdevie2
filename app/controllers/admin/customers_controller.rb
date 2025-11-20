class Admin::CustomersController < Admin::BaseController
  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)

    if @customer.save
      redirect_to new_admin_order_path(customer_id: @customer.id), notice: 'Client créé'
    elsif (existing_customer = Customer.find_by(phone_e164: @customer.phone_e164))
      redirect_to new_admin_order_path(customer_id: existing_customer.id), alert: 'Client déjà existant, vous pouvez créer une commande.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def customer_params
    params.require(:customer).permit(:first_name, :last_name, :phone_e164, :email)
  end
end

