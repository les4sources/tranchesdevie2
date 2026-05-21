class Customers::SessionsController < ApplicationController
  def new
    redirect_to customers_account_path if customer_signed_in?
    @phone_e164 = session[:phone_e164]
  end

  def create
    phone_e164 = normalize_phone(params[:phone_e164])

    unless valid_e164?(phone_e164)
      flash.now[:alert] = 'Format de téléphone invalide'
      render :new, status: :unprocessable_entity
      return
    end

    # Si un code OTP est fourni, vérifier
    if params[:otp_code].present?
      result = OtpService.verify_otp(phone_e164, params[:otp_code])

      if result[:success]
        # Trouver ou créer le client
        customer = Customer.find_or_create_by(phone_e164: phone_e164)

        # Créer la session
        session[:customer_id] = customer.id
        session[:customer_authenticated_at] = Time.current.to_i

        redirect_to customers_account_path, notice: 'Connexion réussie'
      else
        flash.now[:alert] = result[:error]
        @phone_e164 = phone_e164
        render :new, status: :unprocessable_entity
      end
    else
      # Envoyer le code OTP (par SMS, ou par e-mail en secours)
      channel = params[:channel] == 'email' ? :email : :sms
      result = OtpService.send_otp(phone_e164, channel: channel)

      if result[:success]
        session[:phone_e164] = phone_e164
        sent_time = Time.current.strftime('%H:%M')
        flash.now[:notice] = channel == :email ? "Code envoyé par e-mail à #{sent_time}" : "Code envoyé par SMS à #{sent_time}"
        @phone_e164 = phone_e164
        render :new
      else
        flash.now[:alert] = result[:error]
        @phone_e164 = phone_e164
        render :new, status: :unprocessable_entity
      end
    end
  end

  def destroy
    session[:customer_id] = nil
    session[:customer_authenticated_at] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
    redirect_to root_path, notice: 'Déconnexion réussie'
  end

  private

  def normalize_phone(phone)
    return nil if phone.blank?

    # Retirer tous les caractères non numériques sauf le +
    phone = phone.gsub(/[^\d+]/, '')
    # Si ça commence par 0, remplacer par +32 (Belgique)
    phone = phone.sub(/^0/, '+32') if phone.start_with?('0')
    # Si ça ne commence pas par +, ajouter +32
    phone = "+32#{phone}" unless phone.start_with?('+')
    phone
  end

  def valid_e164?(phone)
    phone.present? && phone.match?(/\A\+[1-9]\d{1,14}\z/)
  end
end

