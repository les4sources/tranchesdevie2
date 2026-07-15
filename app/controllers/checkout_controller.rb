class CheckoutController < ApplicationController
  # Prénom vide pour un nouveau client (erreur utilisateur, pas un incident) :
  # levée AVANT le save! du client pour rendre un 422 ciblé plutôt que de laisser
  # remonter un ActiveRecord::RecordInvalid muet vers Sentry (#135, TRANCHESDEVIE-G/H).
  class BlankFirstNameError < StandardError; end

  # Point de retrait inconnu ou supprimé (#148). Erreur utilisateur (page périmée,
  # requête forgée) → 422 ciblé, jamais un 500. Le lieu simplement « non ouvert
  # sur la fournée » est lui rejeté par OrderCreationService.
  class UnknownPickupLocationError < StandardError; end

  PICKUP_LOCATION_ERROR = "Le point de retrait choisi n'est pas disponible.".freeze

  # Espace de nommage du verrou consultatif « paiement portefeuille » (forme à
  # deux entiers). Postgres traite pg_advisory_xact_lock(int8) et (int4,int4)
  # dans des espaces DISTINCTS : aucune collision possible avec le verrou
  # bake_day (mono-argument) pris par OrderCreationService.
  WALLET_ORDER_LOCK_NAMESPACE = 8_100

  before_action :ensure_cart_not_empty, except: [ :success ]
  before_action :ensure_bake_day_set, except: [ :success ]
  # Garde-fou (#68) : on resynchronise la ligne forfait Pizza party AVANT de
  # calculer le total / créer le PaymentIntent ou la commande, au cas où le
  # panier aurait été modifié hors des actions du CartController. Idempotent.
  before_action :sync_pizza_party_forfait!, only: [ :new, :create_payment_intent, :create_cash_order, :create_wallet_order ]
  before_action :ensure_cutoff_not_passed, only: [ :new, :create_payment_intent, :create_cash_order, :create_wallet_order ]

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
    # Paiement en ligne par défaut ; le cash n'est proposé qu'aux clients
    # explicitement autorisés par l'admin (#36).
    @cash_payment_allowed = @customer&.cash_payment_allowed? || false

    # Option portefeuille : proposée uniquement à un client déjà connu dont le
    # solde DISPONIBLE (hors argent réservé aux commandes planifiées calendrier)
    # couvre le total. Le serveur revérifie sous verrou au moment du paiement.
    @wallet = @customer&.persisted? ? @customer.wallet : nil
    @wallet_available_cents = @wallet&.available_balance_cents || 0
    @wallet_payment_available = @wallet.present? && @total_cents.positive? && @wallet_available_cents >= @total_cents

    # Points de retrait ouverts sur la fournée choisie (#148). Le lieu par défaut
    # est pré-sélectionné.
    @pickup_locations = @bake_day.open_pickup_locations
    @selected_pickup_location = @pickup_locations.find(&:default?) || @pickup_locations.first
  end

  def verify_phone
    phone_e164 = normalize_phone(params[:phone_e164])

    unless valid_e164?(phone_e164)
      render json: { success: false, error: "Format de téléphone invalide" }, status: :unprocessable_entity
      return
    end

    if params[:channel] == "email"
      result = OtpService.send_otp(phone_e164, channel: :email, email: params[:email], allow_email_entry: true)

      if result[:success]
        session[:phone_e164] = phone_e164
        session[:email] = result[:email]
        render json: { success: true, message: "Code envoyé par e-mail à " + Time.current.strftime("%H:%M") }
      elsif result[:need_email]
        render json: { success: false, need_email: true, error: result[:error] }, status: :unprocessable_entity
      else
        render json: { success: false, error: result[:error] }, status: :unprocessable_entity
      end
      return
    end

    result = OtpService.send_otp(phone_e164)

    if result[:success]
      session[:phone_e164] = phone_e164
      render json: { success: true, message: "Code envoyé par SMS à " + Time.current.strftime("%H:%M") }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def verify_otp
    phone_e164 = session[:phone_e164]

    unless phone_e164
      render json: { success: false, error: "Veuillez d'abord vérifier votre numéro" }, status: :unprocessable_entity
      return
    end

    result = OtpService.verify_otp(phone_e164, params[:code])

    if result[:success]
      # Plus de compte fantôme (cf. cliente absente des « Mangeurs »). L'ancien
      # `find_or_create_by(phone)` échouait EN SILENCE car `first_name` est
      # obligatoire : la session passait « vérifiée » avec un `customer_id` nil et
      # aucun client en base. On réutilise désormais le client existant ; sinon on
      # le crée DÈS QUE le prénom est disponible (déjà saisi dans le formulaire de
      # checkout, transmis par le JS). Sans prénom, on ne pose AUCUN customer_id
      # factice : le compte sera créé à la commande, où le prénom est requis et
      # l'échec devient explicite.
      customer = Customer.find_by(phone_e164: phone_e164)

      if customer.nil? && params[:first_name].to_s.strip.present?
        customer = Customer.new(
          phone_e164: phone_e164,
          first_name: params[:first_name].to_s.strip,
          last_name: params[:last_name].presence
        )

        unless customer.save
          capture_checkout_issue(
            "otp_customer_create_failed",
            level: :warning,
            extra: { validation_errors: customer.errors.full_messages, phone_suffix: phone_e164.to_s.last(3) }
          )
          customer = nil
        end
      end

      session[:otp_verified] = true
      session[:otp_verified_at] = Time.current.to_i

      if customer&.persisted?
        session[:customer_id] = customer.id
        session[:customer_authenticated_at] = Time.current.to_i
        session[:first_name] = customer.first_name
        session[:last_name] = customer.last_name
      else
        # Prénom pas encore fourni : on NE pose pas de customer_id factice.
        session[:customer_id] = nil
        session[:first_name] = params[:first_name].presence
        session[:last_name] = params[:last_name].presence
      end

      render json: { success: true }
    else
      render json: { success: false, error: result[:error] }, status: :unprocessable_entity
    end
  end

  def create_payment_intent
    unless phone_verified? || customer_signed_in?
      render json: { error: "Phone verification required" }, status: :unauthorized
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
    if json_params["first_name"].present?
      session[:first_name] = json_params["first_name"]
    end
    if json_params["last_name"].present?
      session[:last_name] = json_params["last_name"]
    end
    if json_params["email"].present?
      session[:email] = json_params["email"]
    end

    @bake_day = BakeDay.find_by(id: session[:bake_day_id])
    @cart = session[:cart] || []

    # Jusqu'ici `BakeDay.find` levait un 500 si la session avait perdu le jour ;
    # on rend l'erreur explicite et tracée plutôt que muette.
    unless @bake_day
      capture_checkout_issue("bake_day_missing", level: :warning)
      render json: { error: "Jour de cuisson introuvable" }, status: :unprocessable_entity
      return
    end

    customer = find_or_create_customer(json_params)

    # Réserver la capacité AVANT de prendre l'argent : on crée la commande
    # (statut pending) sous verrou consultatif + contrôle de capacité. Une commande
    # pending compte dans la capacité, donc deux clients ne peuvent pas réserver le
    # même dernier créneau, et une page périmée est bloquée ici (pas de PaymentIntent).
    service = OrderCreationService.new(
      customer: customer,
      bake_day: @bake_day,
      cart_items: @cart,
      payment_method: "online",
      group_name: json_params["group_name"],
      pickup_location: requested_pickup_location(json_params)
    )
    order = service.call

    unless order
      # Rejet de validation/capacité : c'était un 422 muet (aucune trace Sentry).
      # On le remonte avec le panier + le jour pour pouvoir diagnostiquer.
      capture_checkout_issue("order_creation_rejected", level: :warning, extra: { service_errors: service.errors })
      render json: { error: service.errors.join(". ") }, status: :unprocessable_entity
      return
    end

    phone_e164 = customer.phone_e164.presence || session[:phone_e164]

    begin
      payment_intent = Stripe::PaymentIntent.create({
        amount: order.total_cents,
        currency: "eur",
        automatic_payment_methods: {
          enabled: true
        },
        metadata: {
          order_id: order.id,
          bake_day_id: @bake_day.id,
          phone_e164: phone_e164
        }
      })
    rescue Stripe::StripeError => e
      order.destroy # libère la capacité réservée si Stripe échoue
      capture_checkout_issue("stripe_payment_intent_failed", exception: e)
      render json: { error: e.message }, status: :unprocessable_entity
      return
    end

    order.update!(payment_intent_id: payment_intent.id)
    session[:payment_intent_id] = payment_intent.id

    render json: {
      client_secret: payment_intent.client_secret,
      payment_intent_id: payment_intent.id
    }
  rescue UnknownPickupLocationError
    render json: { error: PICKUP_LOCATION_ERROR }, status: :unprocessable_entity
  rescue BlankFirstNameError
    # Prénom vide (erreur utilisateur, pas un incident) : 422 ciblé sur le champ,
    # jamais remonté en erreur Sentry. On log en warning pour l'observabilité.
    Rails.logger.warn("[checkout] first_name_blank — #{checkout_sentry_context.inspect}")
    render json: { error: "Merci d'indiquer ton prénom pour continuer.", field: "first_name" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    # Échec d'enregistrement du client (first_name vide, e-mail en doublon, …) :
    # c'était un 500 muet. On le remonte avec les erreurs de validation et on
    # répond proprement au lieu de planter le tunnel.
    capture_checkout_issue("customer_save_failed", exception: e, extra: { validation_errors: e.record&.errors&.full_messages })
    render json: { error: "Impossible d'enregistrer vos informations. Vérifie ton nom et ton e-mail." }, status: :unprocessable_entity
  rescue StandardError => e
    capture_checkout_issue("create_payment_intent_unexpected_error", exception: e)
    render json: { error: "Une erreur est survenue. Merci de réessayer." }, status: :internal_server_error
  end

  def create_cash_order
    unless phone_verified? || customer_signed_in?
      render json: { success: false, error: "Phone verification required" }, status: :unauthorized
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
    if json_params["first_name"].present?
      session[:first_name] = json_params["first_name"]
    end
    if json_params["last_name"].present?
      session[:last_name] = json_params["last_name"]
    end
    if json_params["email"].present?
      session[:email] = json_params["email"]
    end

    # Vérifier que nous avons les informations nécessaires
    phone_e164 = if customer_signed_in?
                   current_customer.phone_e164
    else
                   session[:phone_e164]
    end

    unless phone_e164 && session[:bake_day_id] && session[:cart]&.any?
      render json: { success: false, error: "Informations manquantes" }, status: :unprocessable_entity
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

    # Garde-fou serveur (#36) : la commande sans paiement en ligne n'est possible
    # que pour les clients explicitement autorisés au cash. Empêche tout
    # contournement du paiement en ligne (page périmée, requête forgée, etc.).
    unless customer.cash_payment_allowed?
      render json: { success: false, error: "Le paiement en ligne est requis pour cette commande" }, status: :forbidden
      return
    end

    bake_day = BakeDay.find_by(id: session[:bake_day_id])
    unless bake_day
      render json: { success: false, error: "Jour de cuisson introuvable" }, status: :unprocessable_entity
      return
    end

    cart_items = session[:cart] || []

    # Use OrderCreationService to create order with cash payment method
    service = OrderCreationService.new(
      customer: customer,
      bake_day: bake_day,
      cart_items: cart_items,
      payment_method: "cash",
      group_name: json_params["group_name"],
      pickup_location: requested_pickup_location(json_params)
    )

    order = service.call

    unless order
      render json: { success: false, error: service.errors.join(", ") }, status: :unprocessable_entity
      return
    end

    # Send order confirmation email (idempotent via EmailMessage guard)
    OrderNotificationService.send_confirmation(order)

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
  rescue UnknownPickupLocationError
    render json: { success: false, error: PICKUP_LOCATION_ERROR }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("Error creating cash order: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    Sentry.capture_exception(e) if defined?(Sentry)
    render json: { success: false, error: "Une erreur est survenue lors de la création de la commande" }, status: :internal_server_error
  end

  # Paiement d'une commande checkout directement depuis le portefeuille du
  # client, sans passer par le calendrier (#friction-portefeuille). Pendant du
  # tunnel Stripe : on réserve la capacité (commande :pending via
  # OrderCreationService), puis on débite le portefeuille de façon atomique
  # (WalletCheckoutService, verrou de ligne). Si le débit échoue (solde
  # insuffisant, course), on détruit la réservation pour libérer la capacité —
  # exactement comme create_payment_intent le fait sur échec Stripe.
  def create_wallet_order
    unless phone_verified? || customer_signed_in?
      render json: { success: false, error: "Phone verification required" }, status: :unauthorized
      return
    end

    begin
      request.body.rewind
      json_params = JSON.parse(request.body.read)
    rescue JSON::ParserError
      json_params = {}
    end

    session[:first_name] = json_params["first_name"] if json_params["first_name"].present?
    session[:last_name] = json_params["last_name"] if json_params["last_name"].present?
    session[:email] = json_params["email"] if json_params["email"].present?

    @bake_day = BakeDay.find_by(id: session[:bake_day_id])
    unless @bake_day
      capture_checkout_issue("bake_day_missing", level: :warning)
      render json: { success: false, error: "Jour de cuisson introuvable" }, status: :unprocessable_entity
      return
    end

    customer = find_or_create_customer(json_params)

    # Le portefeuille suppose un client déjà connu, avec un solde. Un compte tout
    # juste créé n'a pas de portefeuille : on refuse proprement (l'UI ne propose
    # de toute façon l'option qu'aux clients ayant un solde disponible suffisant).
    if customer.wallet.nil?
      render json: { success: false, error: "Aucun portefeuille disponible pour ce compte" }, status: :unprocessable_entity
      return
    end

    # Résolu AVANT la transaction : une levée sous le verrou consultatif ne doit
    # pas remonter au travers du rollback.
    pickup_location = requested_pickup_location(json_params)

    paid_order = nil
    wallet_error = nil

    # Garde d'idempotence : contrairement au paiement Bancontact (clé =
    # payment_intent_id), le paiement portefeuille n'a pas de clé Stripe. Deux
    # soumissions concurrentes (double onglet / double-clic / retry) créeraient
    # deux commandes + double débit. On sérialise sur un verrou consultatif par
    # client (espace de verrou distinct de celui du bake_day, cf.
    # OrderCreationService), et on renvoie une commande portefeuille récente
    # identique si elle existe déjà — la 2e requête concurrente retombe dessus au
    # lieu de re-débiter.
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_xact_lock(#{WALLET_ORDER_LOCK_NAMESPACE}, #{customer.id})"
      )

      existing = recent_wallet_order_for(customer, @bake_day)
      if existing
        paid_order = existing
      else
        service = OrderCreationService.new(
          customer: customer,
          bake_day: @bake_day,
          cart_items: session[:cart] || [],
          payment_method: "wallet",
          group_name: json_params["group_name"],
          pickup_location: pickup_location
        )
        created = service.call

        unless created
          wallet_error = service.errors.join(". ")
          capture_checkout_issue("order_creation_rejected", level: :warning, extra: { service_errors: service.errors })
          raise ActiveRecord::Rollback
        end

        wallet_payment = WalletCheckoutService.new(created)
        unless wallet_payment.call
          wallet_error = wallet_payment.error
          raise ActiveRecord::Rollback # annule la réservation ET le débit d'un bloc
        end

        paid_order = created # assigné UNIQUEMENT si tout a réussi (sinon rollback)
      end
    end

    unless paid_order
      render json: { success: false, error: wallet_error || "Paiement par portefeuille impossible" }, status: :unprocessable_entity
      return
    end

    order = paid_order

    # Confirmation alignée sur le paiement Bancontact (email, idempotent via
    # EmailMessage — sûr même si une requête concurrente retombe sur la commande).
    OrderNotificationService.send_confirmation(order)

    # Alerte solde bas — convention du flux portefeuille (cf. commandes planifiées).
    if customer.wallet.reload.low_balance?
      SmsService.send_low_balance_alert(customer)
    end

    session[:cart] = []
    session[:bake_day_id] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
    session[:first_name] = nil
    session[:last_name] = nil
    session[:email] = nil

    render json: { success: true, order_token: order.public_token }
  rescue UnknownPickupLocationError
    render json: { success: false, error: PICKUP_LOCATION_ERROR }, status: :unprocessable_entity
  rescue BlankFirstNameError
    # Prénom vide (erreur utilisateur) : 422 ciblé, comme le tunnel Stripe (#135/#143).
    Rails.logger.warn("[checkout] first_name_blank (wallet) — #{checkout_sentry_context.inspect}")
    render json: { success: false, error: "Merci d'indiquer ton prénom pour continuer.", field: "first_name" }, status: :unprocessable_entity
  rescue StandardError => e
    capture_checkout_issue("create_wallet_order_unexpected_error", exception: e)
    render json: { success: false, error: "Une erreur est survenue lors du paiement par portefeuille" }, status: :internal_server_error
  end

  def success
    # Handle both payment_intent (online) and order_token (cash) parameters
    # Strip any whitespace or quotes from payment_intent_id
    payment_intent_id = params[:payment_intent]&.strip&.gsub(/^['"]|['"]$/, "")
    order_token = params[:order_token]
    redirect_status = params[:redirect_status]

    if redirect_status.present? && redirect_status != "succeeded"
      Rails.logger.warn("Payment redirect_status=#{redirect_status} for payment_intent=#{payment_intent_id}")
      flash[:alert] = "Le paiement a été refusé ou interrompu. Aucun débit n'a été effectué."
      redirect_to new_checkout_path
      return
    end

    if order_token.present?
      # Cash order - find by public_token
      @order = Order.find_by(public_token: order_token)
      unless @order
        Rails.logger.error("Cash order not found with token: #{order_token}")
        flash[:alert] = "Commande non trouvée"
        redirect_to cart_path
        return
      end
    elsif payment_intent_id.present?
      Rails.logger.info("Processing success page for payment_intent: #{payment_intent_id}")

      # La commande a été créée (réservée) au moment du paiement. On la retrouve
      # par son payment_intent_id ; on laisse un court délai au cas où une requête
      # concurrente la termine.
      @order = find_order_by_payment_intent(payment_intent_id)
      unless @order
        sleep(1.0)
        @order = find_order_by_payment_intent(payment_intent_id)
      end

      unless @order
        Rails.logger.error("Success: commande introuvable pour PI #{payment_intent_id}")
        flash[:alert] = "Commande introuvable. Si tu as été débité, contacte-nous avec la référence : " + payment_intent_id
        redirect_to cart_path
        return
      end

      # Encaisser (idempotent) si Stripe confirme le paiement — la page success
      # double le webhook en cas de retard de ce dernier.
      finalize_order_payment(@order, payment_intent_id)

      Rails.logger.info("Order #{@order.id} retrieved for payment_intent: #{payment_intent_id}")
    else
      Rails.logger.error("Success page called without payment_intent or order_token")
      redirect_to cart_path, alert: "Paramètre manquant"
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

  # Resynchronise la ligne forfait Pizza party (#68). Idempotent.
  def sync_pizza_party_forfait!
    session[:cart] = PizzaPartyForfaitService.sync(session[:cart])
  end

  # Journalise + remonte sur Sentry une anomalie du tunnel de paiement EN LIGNE.
  # Ce tunnel était jusqu'ici muet : un rejet de validation/capacité ou un échec
  # Stripe ne faisait qu'un `render json`, sans aucune trace. On y attache un
  # contexte exploitable (panier, jour, client) sans PII (téléphone réduit au
  # suffixe). `exception:` → capture_exception ; sinon capture_message.
  def capture_checkout_issue(label, level: :error, exception: nil, extra: {})
    context = checkout_sentry_context.merge(extra)
    Rails.logger.error("[checkout] #{label} — #{context.inspect}")
    return unless defined?(Sentry)

    Sentry.with_scope do |scope|
      scope.set_context("checkout", context)
      scope.set_tags(checkout_step: label)
      if exception
        Sentry.capture_exception(exception)
      else
        Sentry.capture_message("[checkout] #{label}", level: level)
      end
    end
  rescue StandardError => e
    # L'observabilité ne doit jamais casser le tunnel.
    Rails.logger.error("[checkout] capture_checkout_issue a échoué: #{e.message}")
  end

  def checkout_sentry_context
    cart = session[:cart] || []
    phone = (session[:phone_e164] || current_customer&.phone_e164).to_s
    {
      bake_day_id: session[:bake_day_id],
      cart_variant_ids: cart.map { |item| item["product_variant_id"] },
      cart_size: cart.sum { |item| item["qty"].to_i },
      customer_id: session[:customer_id],
      customer_signed_in: customer_signed_in?,
      phone_present: phone.present?,
      phone_suffix: phone.last(3)
    }
  end

  # Commande portefeuille récente identique (même client, même jour de cuisson,
  # déjà payée par débit de portefeuille), pour l'idempotence des soumissions
  # concurrentes. Fenêtre courte : cible les double-soumissions accidentelles,
  # pas une vraie 2e commande passée plus tard. À appeler SOUS le verrou client.
  def recent_wallet_order_for(customer, bake_day)
    customer.orders
            .where(bake_day: bake_day, source: :checkout, status: :paid)
            .where(created_at: 1.minute.ago..)
            .joins(:wallet_transactions)
            .where(wallet_transactions: { transaction_type: WalletTransaction.transaction_types[:order_debit] })
            .order(created_at: :desc)
            .first
  end

  def find_order_by_payment_intent(payment_intent_id)
    return nil unless payment_intent_id.present?

    Order.uncached { Order.find_by(payment_intent_id: payment_intent_id) }
  end

  # Point de retrait demandé par le client (#148). Absent → nil, et le modèle
  # retombe alors sur le lieu par défaut de la fournée. Inconnu ou supprimé →
  # on lève, plutôt que de retomber silencieusement sur un autre lieu.
  def requested_pickup_location(json_params)
    id = json_params["pickup_location_id"]
    return nil if id.blank?

    PickupLocation.not_deleted.find_by(id: id) || raise(UnknownPickupLocationError)
  end

  def ensure_cart_not_empty
    redirect_to cart_path, alert: "Votre panier est vide" if (session[:cart] || []).empty?
  end

  def ensure_bake_day_set
    unless session[:bake_day_id]
      redirect_to cart_path, alert: "Veuillez sélectionner un jour de cuisson"
    end
  end

  def ensure_cutoff_not_passed
    @bake_day = BakeDay.find_by(id: session[:bake_day_id])
    if @bake_day&.cut_off_passed?
      redirect_to cart_path, alert: "Le délai de commande pour ce jour est dépassé"
    end
  end

  def calculate_subtotal
    (session[:cart] || []).sum do |item|
      item["qty"].to_i * item["price_cents"].to_i
    end
  end

  def calculate_discount(subtotal, customer)
    return 0 unless customer&.effective_discount_percent&.positive?

    (subtotal * customer.effective_discount_percent / 100.0).round
  end

  def normalize_phone(phone)
    phone.to_s.strip.gsub(/\s/, "")
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
      update_attrs[:first_name] = json_params["first_name"] if json_params["first_name"].present?
      update_attrs[:last_name] = json_params["last_name"] if json_params["last_name"].present?
      update_attrs[:email] = json_params["email"] if json_params["email"].present?

      customer.update(update_attrs) if update_attrs.any?
    else
      phone_e164 = session[:phone_e164]
      customer = Customer.find_or_initialize_by(phone_e164: phone_e164)

      if customer.new_record?
        first_name = (json_params["first_name"] || params[:first_name] || session[:first_name]).to_s.strip
        # Filet AVANT le save! : un prénom vide (ou seulement des espaces) est une
        # erreur utilisateur — on la traite en 422 ciblé plutôt qu'en RecordInvalid
        # muet remonté vers Sentry (#135).
        raise BlankFirstNameError if first_name.blank?

        customer.assign_attributes(
          first_name: first_name,
          last_name: (json_params["last_name"] || params[:last_name] || session[:last_name]).to_s.strip.presence,
          email: (json_params["email"] || params[:email] || session[:email]).to_s.strip.presence
        )
        customer.save!
      end

      # Update customer info if provided (valeurs strippées : on n'écrase jamais
      # avec des espaces seuls, cohérent avec la validation du prénom ci-dessus).
      if json_params["first_name"].present? || json_params["last_name"].present? || json_params["email"].present?
        customer.update(
          first_name: json_params["first_name"].to_s.strip.presence || customer.first_name,
          last_name: json_params["last_name"].to_s.strip.presence || customer.last_name,
          email: json_params["email"].to_s.strip.presence || customer.email
        ) if json_params.any?
      end
    end

    session[:first_name] = customer.first_name
    session[:last_name] = customer.last_name
    session[:email] = customer.email

    customer
  end

  # Encaisse (idempotent) une commande déjà réservée, si Stripe confirme le
  # paiement. Ne crée jamais de commande : la réservation a lieu au moment du
  # paiement (create_payment_intent).
  def finalize_order_payment(order, payment_intent_id)
    payment_intent = Stripe::PaymentIntent.retrieve(payment_intent_id)
    return order unless payment_intent.status == "succeeded"

    OrderPaymentFinalizer.call(order: order, payment_intent_id: payment_intent_id)
  rescue Stripe::StripeError => e
    Rails.logger.error("Erreur récupération PaymentIntent #{payment_intent_id}: #{e.message}")
    order
  rescue StandardError => e
    Rails.logger.error("Erreur finalisation commande #{order&.id} (PI #{payment_intent_id}): #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    order
  end
end
