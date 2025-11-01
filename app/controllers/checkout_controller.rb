class CheckoutController < ApplicationController
  before_action :ensure_cart_not_empty
  before_action :ensure_bake_day_set
  before_action :ensure_cutoff_not_passed, only: [:new, :create_payment_intent]

  def new
    @cart = session[:cart] || []
    @bake_day = BakeDay.find(session[:bake_day_id])
    @total_cents = calculate_total
    @customer = Customer.new
    @otp_verified = session[:otp_verified] == true
  end

  def verify_phone
    phone_e164 = normalize_phone(params[:phone_e164])

    unless valid_e164?(phone_e164)
      render json: { success: false, error: 'Format de téléphone invalide' }, status: :unprocessable_entity
      return
    end

    result = OtpService.send_otp(phone_e164)

    if result[:success]
      session[:phone_e164] = phone_e164
      render json: { success: true, message: 'Code envoyé par SMS' }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def verify_otp
    phone_e164 = session[:phone_e164]

    unless phone_e164
      render json: { success: false, error: 'Veuillez d\'abord vérifier votre numéro' }, status: :unprocessable_entity
      return
    end

    result = OtpService.verify_otp(phone_e164, params[:code])

    if result[:success]
      session[:otp_verified] = true
      render json: { success: true }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def create_payment_intent
    unless session[:otp_verified]
      render json: { error: 'Phone verification required' }, status: :unauthorized
      return
    end

    @bake_day = BakeDay.find(session[:bake_day_id])
    @cart = session[:cart] || []
    total_cents = calculate_total

    customer = find_or_create_customer

    payment_intent = Stripe::PaymentIntent.create({
      amount: total_cents,
      currency: 'eur',
      payment_method_types: ['card', 'bancontact'],
      automatic_payment_methods: {
        enabled: true
      },
      metadata: {
        bake_day_id: @bake_day.id,
        customer_id: customer.id,
        cart_items: @cart.to_json
      }
    })

    session[:payment_intent_id] = payment_intent.id

    render json: {
      client_secret: payment_intent.client_secret,
      payment_intent_id: payment_intent.id
    }
  rescue Stripe::StripeError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def success
    payment_intent_id = params[:payment_intent]
    @order = Order.find_by(payment_intent_id: payment_intent_id)

    unless @order
      redirect_to cart_path, alert: 'Commande non trouvée'
      return
    end

    # Clear cart and session data
    session[:cart] = []
    session[:bake_day_id] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:payment_intent_id] = nil
  end

  private

  def ensure_cart_not_empty
    redirect_to cart_path, alert: 'Votre panier est vide' if (session[:cart] || []).empty?
  end

  def ensure_bake_day_set
    unless session[:bake_day_id]
      redirect_to cart_path, alert: 'Veuillez sélectionner un jour de cuisson'
    end
  end

  def ensure_cutoff_not_passed
    @bake_day = BakeDay.find_by(id: session[:bake_day_id])
    if @bake_day&.cut_off_passed?
      redirect_to cart_path, alert: 'Le délai de commande pour ce jour est dépassé'
    end
  end

  def calculate_total
    (session[:cart] || []).sum do |item|
      item['qty'].to_i * item['price_cents'].to_i
    end
  end

  def normalize_phone(phone)
    phone.to_s.strip.gsub(/\s/, '')
  end

  def valid_e164?(phone)
    phone.match?(/\A\+[1-9]\d{1,14}\z/)
  end

  def find_or_create_customer
    phone_e164 = session[:phone_e164]
    customer = Customer.find_or_initialize_by(phone_e164: phone_e164)

    if customer.new_record?
      customer.assign_attributes(
        first_name: params[:first_name] || session[:first_name],
        last_name: params[:last_name] || session[:last_name],
        email: params[:email] || session[:email]
      )
      customer.save!
    end

    session[:first_name] = customer.first_name
    session[:last_name] = customer.last_name
    session[:email] = customer.email

    customer
  end
end

