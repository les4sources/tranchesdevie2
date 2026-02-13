class CheckoutController < ApplicationController
  before_action :ensure_cart_not_empty, except: [:success]
  before_action :ensure_bake_day_set, except: [:success]
  before_action :ensure_cutoff_not_passed, only: [:new, :create_payment_intent, :create_cash_order]

  def new
    @cart = session[:cart] || []
    @bake_day = BakeDay.find(session[:bake_day_id])
    @subtotal_cents = calculate_subtotal
    
    # Utiliser le client connecté s'il existe, sinon créer un nouveau client
    if customer_signed_in?
      @customer = current_customer
      # Mettre à jour la session avec les données du client connecté
      # (phone_verified? le fait déjà, mais on s'assure que tout est synchronisé)
      session[:phone_e164] = current_customer.phone_e164
      session[:otp_verified] = true
      session[:otp_verified_at] = Time.current.to_i
    else
      @customer = Customer.find_by(phone_e164: session[:phone_e164]) || Customer.new
    end
    
    @discount_cents = calculate_discount(@subtotal_cents, @customer)
    @total_cents = @subtotal_cents - @discount_cents
    @otp_verified = phone_verified?
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
      # Trouver ou créer le client
      customer = Customer.find_or_create_by(phone_e164: phone_e164)

      # Créer la session client complète
      session[:customer_id] = customer.id
      session[:customer_authenticated_at] = Time.current.to_i
      session[:otp_verified] = true
      session[:otp_verified_at] = Time.current.to_i
      render json: { success: true }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def create_payment_intent
    unless phone_verified? || customer_signed_in?
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
    subtotal_cents = calculate_subtotal
    
    # Obtenir le client pour calculer la remise
    customer = if customer_signed_in?
                 current_customer
               else
                 Customer.find_by(phone_e164: session[:phone_e164])
               end
    
    discount_cents = calculate_discount(subtotal_cents, customer)
    total_cents = subtotal_cents - discount_cents

    # Utiliser le phone_e164 du client connecté si disponible, sinon celui de la session
    phone_e164 = if customer_signed_in?
                   current_customer.phone_e164
                 else
                   session[:phone_e164]
                 end

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

  def create_cash_order
    unless phone_verified? || customer_signed_in?
      render json: { success: false, error: 'Phone verification required' }, status: :unauthorized
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

    # Vérifier que nous avons les informations nécessaires
    phone_e164 = if customer_signed_in?
                   current_customer.phone_e164
                 else
                   session[:phone_e164]
                 end

    unless phone_e164 && session[:bake_day_id] && session[:cart]&.any?
      render json: { success: false, error: 'Informations manquantes' }, status: :unprocessable_entity
      return
    end

    # Utiliser le client connecté si disponible, sinon trouver ou créer
    if customer_signed_in?
      customer = current_customer

      # Mettre à jour les informations du client si elles ont été modifiées dans le formulaire
      update_attrs = {}
      update_attrs[:first_name] = session[:first_name] if session[:first_name].present?
      update_attrs[:last_name] = session[:last_name] if session[:last_name].present?
      update_attrs[:email] = session[:email] if session[:email].present?

      customer.update(update_attrs) if update_attrs.any?
    else
      # Find or create customer
      customer = Customer.find_or_create_by(phone_e164: phone_e164)

      if customer.new_record?
        # Use session data or default values (first_name is required)
        customer.assign_attributes(
          first_name: session[:first_name].presence,
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
    end

    bake_day = BakeDay.find_by(id: session[:bake_day_id])
    unless bake_day
      render json: { success: false, error: 'Jour de cuisson introuvable' }, status: :unprocessable_entity
      return
    end

    cart_items = session[:cart] || []

    # Use OrderCreationService to create order with cash payment method
    service = OrderCreationService.new(
      customer: customer,
      bake_day: bake_day,
      cart_items: cart_items,
      payment_method: 'cash'
    )

    order = service.call

    unless order
      render json: { success: false, error: service.errors.join(', ') }, status: :unprocessable_entity
      return
    end

    # Clear cart and session data
    session[:cart] = []
    session[:bake_day_id] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
    session[:first_name] = nil
    session[:last_name] = nil
    session[:email] = nil

    render json: {
      success: true,
      order_token: order.public_token
    }
  rescue StandardError => e
    Rails.logger.error("Error creating cash order: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    Sentry.capture_exception(e) if defined?(Sentry)
    render json: { success: false, error: 'Une erreur est survenue lors de la création de la commande' }, status: :internal_server_error
  end

  def success
    # Handle both payment_intent (online) and order_token (cash) parameters
    # Strip any whitespace or quotes from payment_intent_id
    payment_intent_id = params[:payment_intent]&.strip&.gsub(/^['"]|['"]$/, '')
    order_token = params[:order_token]
    redirect_status = params[:redirect_status]

    if redirect_status.present? && redirect_status != 'succeeded'
      Rails.logger.warn("Payment redirect_status=#{redirect_status} for payment_intent=#{payment_intent_id}")
      flash[:alert] = 'Le paiement a été refusé ou interrompu. Aucun débit n\'a été effectué.'
      redirect_to new_checkout_path
      return
    end

    if order_token.present?
      # Cash order - find by public_token
      @order = Order.find_by(public_token: order_token)
      unless @order
        Rails.logger.error("Cash order not found with token: #{order_token}")
        flash[:alert] = 'Commande non trouvée'
        redirect_to cart_path
        return
      end
    elsif payment_intent_id.present?
      Rails.logger.info("Processing success page for payment_intent: #{payment_intent_id}")
      
      # Online payment - find by payment_intent_id
      @order = find_order_by_payment_intent(payment_intent_id)

      # If order doesn't exist, wait for webhook or try to create it
      unless @order
        Rails.logger.info("Order not found immediately, waiting for webhook...")
        
        # Wait a bit for webhook to process (increased wait time)
        sleep(1.0)
        @order = find_order_by_payment_intent(payment_intent_id)

        # If still not found, try to create it from session data or payment intent metadata
        unless @order
          Rails.logger.info("Order still not found after wait, attempting to create from session/payment intent...")
          @order = create_order_from_session(payment_intent_id)

          # After attempting creation, try one last time to fetch the order (webhook might have finished)
          @order ||= find_order_by_payment_intent(payment_intent_id)
        end
      end

      unless @order
        Rails.logger.error("Failed to find or create order for payment_intent: #{payment_intent_id}. Session data: cart=#{session[:cart]&.size || 0} items, bake_day_id=#{session[:bake_day_id]}, phone_e164=#{session[:phone_e164].present? ? 'present' : 'missing'}")
        flash[:alert] = 'Commande non trouvée. Le paiement a été traité, mais la commande n\'a pas pu être créée. Contactez-nous avec le numéro de paiement: ' + payment_intent_id
        redirect_to cart_path
        return
      end
      
      Rails.logger.info("Order found/created successfully: #{@order.id} for payment_intent: #{payment_intent_id}")
    else
      Rails.logger.error("Success page called without payment_intent or order_token")
      redirect_to cart_path, alert: 'Paramètre manquant'
      return
    end

    # Clear cart and session data only after successful order retrieval/creation
    session[:cart] = []
    session[:bake_day_id] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
    session[:payment_intent_id] = nil
    session[:first_name] = nil
    session[:last_name] = nil
    session[:email] = nil
  end

  private

  def find_order_by_payment_intent(payment_intent_id)
    return nil unless payment_intent_id.present?

    Order.uncached { Order.find_by(payment_intent_id: payment_intent_id) }
  end

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

  def calculate_subtotal
    (session[:cart] || []).sum do |item|
      item['qty'].to_i * item['price_cents'].to_i
    end
  end

  def calculate_discount(subtotal, customer)
    return 0 unless customer&.effective_discount_percent&.positive?

    (subtotal * customer.effective_discount_percent / 100.0).round
  end

  def normalize_phone(phone)
    phone.to_s.strip.gsub(/\s/, '')
  end

  def valid_e164?(phone)
    phone.match?(/\A\+[1-9]\d{1,14}\z/)
  end

  def find_or_create_customer(json_params = {})
    # Utiliser le client connecté si disponible
    if customer_signed_in?
      customer = current_customer
      
      # Mettre à jour les informations si fournies
      update_attrs = {}
      update_attrs[:first_name] = json_params['first_name'] if json_params['first_name'].present?
      update_attrs[:last_name] = json_params['last_name'] if json_params['last_name'].present?
      update_attrs[:email] = json_params['email'] if json_params['email'].present?
      
      customer.update(update_attrs) if update_attrs.any?
    else
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
    end

    session[:first_name] = customer.first_name
    session[:last_name] = customer.last_name
    session[:email] = customer.email

    customer
  end

  def create_order_from_session(payment_intent_id)
    # Use payment_intent_id from parameter or fallback to session
    payment_intent_id = (payment_intent_id || session[:payment_intent_id])&.strip&.gsub(/^['"]|['"]$/, '')
    
    unless payment_intent_id.present?
      Rails.logger.error("No payment_intent_id provided or found in session")
      return nil
    end
    
    Rails.logger.info("Attempting to create order from session for payment_intent: #{payment_intent_id}")
    
    # Retrieve the payment intent to verify it succeeded and get metadata
    metadata = {}
    
    begin
      payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
      
      unless payment_intent.status == 'succeeded'
        Rails.logger.error("Payment intent #{payment_intent_id} status is #{payment_intent.status}, not succeeded")
        return nil
      end
      
      Rails.logger.info("Payment intent #{payment_intent_id} succeeded. Metadata: #{payment_intent.metadata.inspect}")
      metadata = payment_intent.metadata || {}
    rescue Stripe::StripeError => e
      Rails.logger.error("Error retrieving payment intent #{payment_intent_id}: #{e.message}")
      return nil
    end

    # Try to get data from session first, fallback to payment intent metadata
    # Metadata is a hash, access with bracket notation
    
    phone_e164 = if customer_signed_in?
                   current_customer.phone_e164
                 elsif session[:phone_e164].present?
                   session[:phone_e164]
                 else
                   metadata[:phone_e164] || metadata['phone_e164']
                 end
    
    bake_day_id = session[:bake_day_id] || metadata[:bake_day_id] || metadata['bake_day_id']
    cart_items_json = if session[:cart]&.present?
                       session[:cart]
                     else
                       metadata[:cart_items] || metadata['cart_items']
                     end
    
    # Parse cart items if it's a JSON string
    cart_items = if cart_items_json.is_a?(String)
                   JSON.parse(cart_items_json) rescue []
                 elsif cart_items_json.is_a?(Array)
                   cart_items_json
                 else
                   []
                 end

    # Validate required data
    unless phone_e164.present?
      Rails.logger.error("No phone_e164 found in session or payment intent metadata")
      return nil
    end

    unless bake_day_id.present?
      Rails.logger.error("No bake_day_id found in session or payment intent metadata")
      return nil
    end

    unless cart_items.any?
      Rails.logger.error("No cart_items found in session or payment intent metadata")
      return nil
    end

    Rails.logger.info("Creating order with phone_e164: #{phone_e164}, bake_day_id: #{bake_day_id}, cart_items: #{cart_items.size} items")

    # Find or create customer
    customer = if customer_signed_in?
                 current_customer.tap do |c|
                   # Update customer info if provided in session
                   update_attrs = {}
                   update_attrs[:first_name] = session[:first_name] if session[:first_name].present?
                   update_attrs[:last_name] = session[:last_name] if session[:last_name].present?
                   update_attrs[:email] = session[:email] if session[:email].present?
                   c.update(update_attrs) if update_attrs.any?
                 end
               else
                 Customer.find_or_create_by(phone_e164: phone_e164).tap do |c|
                   if c.new_record?
                     c.assign_attributes(
                       first_name: session[:first_name].presence,
                       last_name: session[:last_name].presence,
                       email: session[:email].presence
                     )
                     c.save!
                   elsif session[:first_name].present? || session[:last_name].present? || session[:email].present?
                     c.update(
                       first_name: session[:first_name].presence || c.first_name,
                       last_name: session[:last_name].presence || c.last_name,
                       email: session[:email].presence || c.email
                     )
                   end
                 end
               end

    unless customer
      Rails.logger.error("Failed to find or create customer with phone_e164: #{phone_e164}")
      return nil
    end

    bake_day = BakeDay.find_by(id: bake_day_id)
    unless bake_day
      Rails.logger.error("Bake day not found with id: #{bake_day_id}")
      return nil
    end

    # First, check if order already exists (idempotency)
    # This can happen if webhook created it between our checks
    order = find_order_by_payment_intent(payment_intent_id)
    
    if order
      Rails.logger.info("Order already exists for payment_intent #{payment_intent_id}: #{order.id}")
    else
      # Use OrderCreationService to create order
      service = OrderCreationService.new(
        customer: customer,
        bake_day: bake_day,
        cart_items: cart_items,
        payment_intent_id: payment_intent_id
      )

      order = service.call

      unless order
        # If service failed because order exists, try to find it again (race condition)
        if service.errors.any? && service.errors.include?('Order already exists for this payment intent')
          Rails.logger.info("OrderCreationService says order exists, retrying find...")
          # Try again with uncached query
          order = find_order_by_payment_intent(payment_intent_id)
          if order
            Rails.logger.info("Found existing order after retry: #{order.id}")
          else
            Rails.logger.error("OrderCreationService says order exists but we cannot find it for payment_intent #{payment_intent_id}")
          end
        else
          Rails.logger.error("OrderCreationService failed for payment_intent #{payment_intent_id}. Errors: #{service.errors.join(', ')}")
        end
        
        return nil unless order
      end

      Rails.logger.info("Order created successfully: #{order.id} for payment_intent #{payment_intent_id}")
    end

    if order
      order.transition_to!(:paid)
      
      # Create payment record
      Payment.find_or_create_by!(order: order) do |payment|
        payment.stripe_payment_intent_id = payment_intent_id
        payment.status = :succeeded
      end
    end

    order
  rescue StandardError => e
    Rails.logger.error("Error creating order from session for payment_intent #{payment_intent_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    Sentry.capture_exception(e) if defined?(Sentry)
    nil
  end
end

