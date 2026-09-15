# Parcours de DEMANDE d'une Pizza party privée (#pizza-parties).
#
# Hors panier, hors checkout : la demande ne paie rien, donc elle n'a rien à
# faire dans un tunnel conçu pour encaisser dans la même session. Le formulaire
# est autoportant (date, créneau, nombre de personnes, commentaire, coordonnées)
# et la vérification du numéro réutilise les endpoints OTP existants du checkout,
# qui ne touchent que la session.
class PartyRequestsController < ApplicationController
  before_action :load_request_by_token, only: [ :show, :cancel, :sent ]

  def new
    @availability_start = Date.current + PartyRequest::MINIMUM_NOTICE_DAYS
    @availability = PartyRequest.requestable_availability(@availability_start..(@availability_start + 8.weeks))
    @party_variant = Product.pizza_party_variant(:party)
    @forfait_variant = Product.pizza_party_variant(:forfait)
    @customer = current_customer
  end

  def create
    unless otp_verified?
      redirect_to new_party_request_path, alert: "Merci de vérifier ton numéro avant d'envoyer ta demande."
      return
    end

    customer = resolve_customer

    if customer.nil?
      flash.now[:alert] = @customer_error || "Merci de compléter tes coordonnées."
      return render_new
    end

    service = PartyRequestService.new(
      customer: customer,
      date: params[:held_on],
      slot: params[:slot].presence || PartyEvent::PRIVATE_SLOT,
      persons: params[:persons],
      customer_note: params[:customer_note],
      group_name: params[:group_name]
    )

    if (party_request = service.call)
      redirect_to party_request_sent_path(token: party_request.public_token)
    else
      flash.now[:alert] = service.errors.to_sentence
      render_new
    end
  end

  # Page de confirmation : « ta demande est envoyée », sans aucun bouton de paiement.
  def sent
  end

  # Suivi d'une demande par son jeton public — pas de compte requis.
  def show
    @order = @party_request.order
  end

  def cancel
    if @party_request.state_pending?
      @party_request.update!(state: :cancelled)
      redirect_to party_request_path(token: @party_request.public_token), notice: "Ta demande a été annulée."
    else
      redirect_to party_request_path(token: @party_request.public_token),
                  alert: "Cette demande ne peut plus être annulée."
    end
  end

  private

  def render_new
    new
    render :new, status: :unprocessable_entity
  end

  def load_request_by_token
    @party_request = PartyRequest.find_by!(public_token: params[:token])
  end

  def otp_verified?
    customer_signed_in? || session[:otp_verified].present?
  end

  # Réutilise le client connecté ou celui du numéro vérifié, et complète ses
  # coordonnées. L'e-mail est obligatoire : sans lui, le client ne recevra jamais
  # son lien de paiement, et sa réservation expirerait en silence.
  def resolve_customer
    email = params[:email].to_s.strip.downcase
    first_name = params[:first_name].to_s.strip
    last_name = params[:last_name].to_s.strip.presence

    if email.blank?
      @customer_error = "Une adresse e-mail est nécessaire : c'est par là que la boulangerie te répondra."
      return nil
    end

    customer = current_customer || Customer.find_by(phone_e164: session[:phone_e164])

    # Un e-mail déjà rattaché à quelqu'un d'autre : on le dit, plutôt que de
    # laisser l'enregistrement échouer en silence sur l'unicité.
    conflict = Customer.where(email: email)
    conflict = conflict.where.not(id: customer.id) if customer
    if conflict.exists?
      @customer_error = "Cette adresse e-mail est déjà utilisée par un autre compte. Connecte-toi ou utilise une autre adresse."
      return nil
    end

    if customer.nil?
      if first_name.blank?
        @customer_error = "Merci d'indiquer ton prénom."
        return nil
      end

      customer = Customer.new(phone_e164: session[:phone_e164], first_name: first_name, last_name: last_name)
    else
      customer.first_name = first_name if first_name.present?
      customer.last_name = last_name if last_name.present?
    end

    customer.email = email

    unless customer.save
      @customer_error = customer.errors.full_messages.to_sentence
      return nil
    end

    customer
  end
end
