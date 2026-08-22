class Customers::SessionsController < ApplicationController
  def new
    redirect_to customers_account_path if customer_signed_in?
    @identifier = session[:login_identifier]
  end

  def create
    # Étape 3 — finaliser l'inscription d'un nouvel identifiant (OTP déjà validé).
    return complete_signup if params[:complete_signup].present?

    # Le client saisit un seul champ : son GSM OU son e-mail (paramètre :identifier).
    # On garde :phone_e164 en repli pour la rétro-compatibilité.
    raw = params[:identifier].presence || params[:phone_e164]
    identifier = OtpService.classify_identifier(raw)

    if identifier[:type] == :invalid
      flash.now[:alert] = OtpService.invalid_identifier_error
      @identifier = raw
      render :new, status: :unprocessable_entity
      return
    end

    canonical = identifier[:phone] || identifier[:email]
    @identifier = canonical

    if params[:otp_code].present?
      verify_and_sign_in(identifier, canonical)
    else
      send_code(canonical)
    end
  end

  def destroy
    reset_login_session
    redirect_to root_path, notice: "Déconnexion réussie"
  end

  private

  def send_code(canonical)
    result = OtpService.send_code(identifier: canonical)

    if result[:success]
      session[:login_identifier] = canonical
      sent_time = Time.current.strftime("%H:%M")
      flash.now[:notice] =
        result[:channel] == :email ? "Code envoyé par e-mail à #{sent_time}" : "Code envoyé par SMS à #{sent_time}"
      render :new
    else
      flash.now[:alert] = result[:error]
      render :new, status: :unprocessable_entity
    end
  end

  def verify_and_sign_in(identifier, canonical)
    result = OtpService.verify_code(identifier: canonical, code: params[:otp_code])

    unless result[:success]
      flash.now[:alert] = result[:error]
      render :new, status: :unprocessable_entity
      return
    end

    customer = find_existing_customer(identifier)

    if customer
      sign_in(customer)
    else
      # Identifiant inconnu : le code est validé, on demande le prénom avant de
      # créer le compte (le modèle exige un prénom). L'identifiant autorisé est
      # mémorisé en session, jamais re-fourni par le client.
      session[:pending_signup_identifier] = canonical
      @identifier = canonical
      @needs_name = true
      flash.now[:notice] = "Code validé ! Plus qu'une étape."
      render :new
    end
  end

  def complete_signup
    canonical = session[:pending_signup_identifier]

    if canonical.blank?
      flash.now[:alert] = "Ta session a expiré, recommence la connexion."
      render :new, status: :unprocessable_entity
      return
    end

    identifier = OtpService.classify_identifier(canonical)
    customer = Customer.new(first_name: params[:first_name].to_s.strip, last_name: params[:last_name].presence)
    if identifier[:type] == :phone
      customer.phone_e164 = identifier[:phone]
    else
      # Compte créé par e-mail : pas de GSM, on saute donc la validation de présence
      # du téléphone (même mécanisme que l'admin).
      customer.email = identifier[:email]
      customer.skip_phone_validation = true
    end

    if customer.save
      session[:pending_signup_identifier] = nil
      sign_in(customer)
    else
      @identifier = canonical
      @needs_name = true
      flash.now[:alert] = customer.errors.full_messages.to_sentence.presence || "Vérifie ton prénom."
      render :new, status: :unprocessable_entity
    end
  end

  # Cherche un compte EXISTANT pour l'identifiant (jamais de création ici).
  # Les e-mails dupliqués hérités sont résolus de façon déterministe.
  def find_existing_customer(identifier)
    if identifier[:type] == :phone
      Customer.find_by(phone_e164: identifier[:phone])
    else
      matches = Customer.where("lower(email) = ?", identifier[:email]).order(:created_at)
      Rails.logger.warn("Login e-mail correspond à plusieurs comptes: #{identifier[:email]}") if matches.size > 1
      matches.first
    end
  end

  def sign_in(customer)
    session[:customer_id] = customer.id
    session[:customer_authenticated_at] = Time.current.to_i
    session[:login_identifier] = nil
    session[:pending_signup_identifier] = nil
    redirect_to customers_account_path, notice: "Connexion réussie"
  end

  def reset_login_session
    session[:customer_id] = nil
    session[:customer_authenticated_at] = nil
    session[:login_identifier] = nil
    session[:pending_signup_identifier] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
  end
end
