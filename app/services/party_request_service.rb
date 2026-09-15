# Dépôt d'une DEMANDE de Pizza party privée (#pizza-parties).
#
# Ne crée ni `PartyEvent` ni `Order` : une demande n'occupe aucun créneau et ne
# consomme aucune capacité. Deux groupes peuvent donc demander la même soirée —
# c'est la boulangerie qui arbitre, à la validation.
#
# Le service FIGE les prix unitaires (et la remise groupe) au moment de la
# demande : c'est le montant annoncé au client, et il ne doit pas bouger si un
# tarif change avant qu'il ne paie. Seule la quantité sera confirmée au paiement.
class PartyRequestService
  attr_reader :party_request, :errors

  def initialize(customer:, date:, slot:, persons:, customer_note:, group_name: nil, forfait: true)
    @customer = customer
    @date = date.is_a?(Date) ? date : safe_date(date)
    @slot = slot.to_s
    @persons = persons.to_i
    @customer_note = customer_note.to_s.strip
    @group_name = group_name.presence
    @forfait = forfait
    @errors = []
  end

  def call
    @errors = []
    return false unless valid?

    ActiveRecord::Base.transaction do
      @party_request = PartyRequest.create!(
        customer: @customer,
        held_on: @date,
        slot: @slot,
        estimated_persons: @persons,
        forfait: @forfait,
        customer_note: @customer_note,
        group_name: @group_name,
        state: :pending
      )

      freeze_lines!
    end

    PartyRequestNotifier.request_received(@party_request)
    @party_request
  end

  private

  def safe_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error, ArgumentError, TypeError
    nil
  end

  def valid?
    @errors << "Client requis" unless @customer
    # Sans e-mail, le client ne pourra jamais recevoir son lien de paiement : tout
    # le dialogue de ce parcours passe par l'e-mail (#pizza-parties).
    @errors << "Une adresse e-mail est nécessaire pour te répondre." if @customer && @customer.email.blank?
    @errors << "Date ou créneau de la Pizza party invalide" unless @date && PartyEvent.slots.key?(@slot)
    @errors << "Merci de nous parler de ton groupe avant d'envoyer ta demande." if @customer_note.blank?
    @errors << "Ton commentaire dépasse #{Order::CUSTOMER_NOTE_MAX_LENGTH} caractères." if @customer_note.length > Order::CUSTOMER_NOTE_MAX_LENGTH
    @errors << "Merci d'indiquer au moins une personne." if @persons < 1

    if @date && PartyEvent.slots.key?(@slot) && !PartyRequest.requestable?(@date, @slot)
      @errors << "Cette date n'est pas disponible. Une Pizza party se réserve au moins #{PartyRequest::MINIMUM_NOTICE_DAYS} jours à l'avance."
    end

    @errors << "Le produit Pizza party n'est pas configuré." if party_variant.nil?

    @errors.empty?
  end

  # Copie les lignes avec leur prix du jour et la remise groupe applicable.
  def freeze_lines!
    lines = [ { variant: party_variant, qty: @persons } ]
    lines << { variant: forfait_variant, qty: 1 } if @forfait && forfait_variant

    discount_cents = GroupDiscountService.new(@customer).total_discount_cents(lines)

    lines.each_with_index do |line, index|
      @party_request.party_request_items.create!(
        product_variant: line[:variant],
        qty: line[:qty],
        unit_price_cents: line[:variant].price_cents,
        # La remise groupe porte sur l'ensemble : on l'impute entièrement à la
        # première ligne (les pâtons), la seule dont la quantité varie.
        discount_cents: index.zero? ? discount_cents : 0
      )
    end
  end

  def party_variant
    @party_variant ||= Product.pizza_party_variant(:party)
  end

  def forfait_variant
    @forfait_variant ||= Product.pizza_party_variant(:forfait)
  end
end
