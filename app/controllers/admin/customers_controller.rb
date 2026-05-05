class Admin::CustomersController < Admin::BaseController
  before_action :set_customer, only: [:show, :edit, :update]

  def index
    @customers = Customer.includes(:orders, :groups)
    
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @customers = @customers.where(
        "first_name ILIKE ? OR last_name ILIKE ? OR phone_e164 ILIKE ? OR email ILIKE ?",
        search_term, search_term, search_term, search_term
      )
    end

    case params[:sort]
    when "orders"
      @customers = @customers.left_joins(:orders)
                              .group("customers.id")
                              .order(Arel.sql("COUNT(orders.id) DESC"))
    when "last_order"
      @customers = @customers.left_joins(:orders)
                              .group("customers.id")
                              .order(Arel.sql("MAX(orders.created_at) DESC NULLS LAST"))
    else
      @customers = @customers.order(:last_name, :first_name)
    end
  end

  def show
    @orders = @customer.orders.includes(:bake_day).order(created_at: :desc)
    @sms_messages = @customer.sms_messages.ordered_by_sent_at
  end

  def new
    @customer = Customer.new
    @groups = Group.order(:name)
  end

  def create
    @customer = Customer.new(customer_params)
    @customer.skip_phone_validation = true if @customer.phone_e164.blank?

    if @customer.save
      redirect_to admin_customers_path, notice: 'Mangeur créé avec succès'
    elsif @customer.phone_e164.present? && (existing_customer = Customer.find_by(phone_e164: @customer.phone_e164))
      redirect_to admin_customer_path(existing_customer), alert: 'Ce mangeur existe déjà. Redirection vers sa page.'
    else
      @groups = Group.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @groups = Group.order(:name)
  end

  def update
    @customer.skip_phone_validation = true if customer_params[:phone_e164].blank?
    
    if @customer.update(customer_params)
      redirect_to admin_customer_path(@customer), notice: 'Mangeur mis à jour avec succès'
    else
      @groups = Group.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_customer
    @customer = Customer.find(params[:id])
  end

  def customer_params
    permitted = params.require(:customer).permit(:first_name, :last_name, :phone_e164, :email, :sms_opt_out, :skip_wallet_check, :billable, group_ids: [])
    # Convertir les chaînes vides en nil pour phone_e164
    permitted[:phone_e164] = nil if permitted[:phone_e164].blank?
    permitted
  end
end

