class CheckoutController < ApplicationController
  before_action :ensure_cart_not_empty
  before_action :ensure_bake_day_set
  before_action :ensure_cutoff_not_passed, only: [:new, :create_payment_intent]

  def new
    @cart = session[:cart] || []
    @bake_day = BakeDay.find(session[:bake_day_id])
    @total_cents = calculate_total
    
    # Utiliser le client connecté s'il existe, sinon créer un nouveau client
    if customer_signed_in?
      @customer = current_customer
    else
      @customer = Customer.new
    end
    
    @otp_verified = phone_verified? || customer_signed_in?
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
      render json: { success: true, message: 'Code envoyé par SMS à ' + Time.current.strftime('%H:%M') }
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
      session[:otp_verified_at] = Time.current.to_i
      render json: { success: true }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def create_payment_intent
    unless phone_verified?
      render json: { error: 'Phone verification required' }, status: :unauthorized
      return
    end

    # Parse JSON body
    begin
      request.body.rewind
      json_params = JSON.parse(request.body.read)
    rescue JSON::ParserError
      json_params = {}
    end
    
    # Store customer info in session if provided
    if json_params['first_name'].present?
      session[:first_name] = json_params['first_name']
    end
    if json_params['last_name'].present?
      session[:last_name] = json_params['last_name']
    end
    if json_params['email'].present?
      session[:email] = json_params['email']
    end
    
    @bake_day = BakeDay.find(session[:bake_day_id])
    @cart = session[:cart] || []
    total_cents = calculate_total

    # Customer will be created during order creation, not here
    phone_e164 = session[:phone_e164]

    payment_intent = Stripe::PaymentIntent.create({
      amount: total_cents,
      currency: 'eur',
      automatic_payment_methods: {
        enabled: true
      },
      metadata: {
        bake_day_id: @bake_day.id,
        phone_e164: phone_e164,
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
    
    unless payment_intent_id.present?
      redirect_to cart_path, alert: 'Paramètre de paiement manquant'
      return
    end

    # Try to find order
    @order = Order.find_by(payment_intent_id: payment_intent_id)

    # If order doesn't exist, try to create it (fallback if webhook hasn't been received yet)
    unless @order
      # Wait a bit for webhook to process
      sleep(0.5)
      @order = Order.find_by(payment_intent_id: payment_intent_id)

      # If still not found, try to create it from session data
      unless @order
        @order = create_order_from_session(payment_intent_id)
      end
    end

    unless @order
      flash[:alert] = 'Commande non trouvée. Le paiement a été traité, mais la commande n\'a pas pu être créée. Contactez-nous avec le numéro de paiement: ' + payment_intent_id
      redirect_to cart_path
      return
    end

    # Clear cart and session data
    session[:cart] = []
    session[:bake_day_id] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
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

  def find_or_create_customer(json_params = {})
    phone_e164 = session[:phone_e164]
    customer = Customer.find_or_initialize_by(phone_e164: phone_e164)

    if customer.new_record?
      customer.assign_attributes(
        first_name: json_params['first_name'] || params[:first_name] || session[:first_name],
        last_name: json_params['last_name'] || params[:last_name] || session[:last_name],
        email: json_params['email'] || params[:email] || session[:email]
      )
      customer.save!
    end

    # Update customer info if provided
    if json_params['first_name'].present? || json_params['last_name'].present? || json_params['email'].present?
      customer.update(
        first_name: json_params['first_name'] || customer.first_name,
        last_name: json_params['last_name'] || customer.last_name,
        email: json_params['email'] || customer.email
      ) if json_params.any?
    end

    session[:first_name] = customer.first_name
    session[:last_name] = customer.last_name
    session[:email] = customer.email

    customer
  end

  def create_order_from_session(payment_intent_id)
    return nil unless session[:phone_e164] && session[:bake_day_id] && session[:cart]&.any?

    # Verify payment intent exists and is succeeded
    begin
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      return nil unless payment_intent.status == 'succeeded'
    rescue Stripe::StripeError => e
      Rails.logger.error("Error retrieving payment intent: #{e.message}")
      return nil
    end

    # Find or create customer
    customer = Customer.find_or_create_by(phone_e164: session[:phone_e164])
    
    if customer.new_record?
      # Use session data or default values (first_name is required)
      customer.assign_attributes(
        first_name: session[:first_name].presence || 'Client',
        last_name: session[:last_name].presence,
        email: session[:email].presence
      )
      customer.save!
    elsif session[:first_name].present? || session[:last_name].present? || session[:email].present?
      # Update customer info if provided in session
      customer.update(
        first_name: session[:first_name].presence || customer.first_name,
        last_name: session[:last_name].presence || customer.last_name,
        email: session[:email].presence || customer.email
      )
    end

    bake_day = BakeDay.find_by(id: session[:bake_day_id])
    return nil unless bake_day

    cart_items = session[:cart] || []

    # Use OrderCreationService to create order
    service = OrderCreationService.new(
      customer: customer,
      bake_day: bake_day,
      cart_items: cart_items,
      payment_intent_id: payment_intent_id
    )

    order = service.call

    if order
      order.transition_to!(:paid)
      
      # Create payment record
      Payment.find_or_create_by!(order: order) do |payment|
        payment.stripe_payment_intent_id = payment_intent_id
        payment.status = :succeeded
      end

      # Send confirmation SMS
      SmsService.send_confirmation(order) rescue nil
    end

    order
  rescue StandardError => e
    Rails.logger.error("Error creating order from session: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end
end

