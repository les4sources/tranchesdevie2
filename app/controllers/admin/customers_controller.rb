class Admin::CustomersController < Admin::BaseController
  before_action :set_customer, only: [:show, :edit, :update, :send_sms]

  def index
    @customers = Customer.order(created_at: :desc).includes(:orders)
    
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @customers = @customers.where(
        "first_name ILIKE ? OR last_name ILIKE ? OR phone_e164 ILIKE ? OR email ILIKE ?",
        search_term, search_term, search_term, search_term
      )
    end
  end

  def show
    @orders = @customer.orders.includes(:bake_day).order(created_at: :desc)
    @sms_messages = @customer.sms_messages.ordered_by_sent_at
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)

    if @customer.save
      redirect_to admin_customers_path, notice: 'Mangeur créé avec succès'
    elsif (existing_customer = Customer.find_by(phone_e164: @customer.phone_e164))
      redirect_to admin_customer_path(existing_customer), alert: 'Ce mangeur existe déjà. Redirection vers sa page.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @customer.update(customer_params)
      redirect_to admin_customer_path(@customer), notice: 'Mangeur mis à jour avec succès'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def send_sms
    body = params[:body]
    
    if body.blank?
      render json: { success: false, error: 'Le message ne peut pas être vide' }, status: :unprocessable_entity
      return
    end

    unless @customer.sms_enabled?
      render json: { success: false, error: 'Les SMS sont désactivés pour ce client' }, status: :unprocessable_entity
      return
    end

    if SmsService.send_custom(@customer, body)
      render json: { success: true, message: 'SMS envoyé avec succès' }
    else
      render json: { success: false, error: 'Erreur lors de l\'envoi du SMS' }, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error("Error sending SMS: #{e.message}")
    render json: { success: false, error: 'Une erreur est survenue' }, status: :unprocessable_entity
  end

  private

  def set_customer
    @customer = Customer.find(params[:id])
  end

  def customer_params
    params.require(:customer).permit(:first_name, :last_name, :phone_e164, :email, :sms_opt_out)
  end
end

