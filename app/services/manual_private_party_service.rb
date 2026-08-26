# frozen_string_literal: true

# Pizza party PRIVÉE créée à la main depuis l'admin (#204).
#
# « Celle-là, elle n'était pas encore dans le système, elle avait commandé par
# mail. » Sans ce chemin, la party n'apparaît nulle part : ni dans l'écran
# Parties, ni sur le jour de cuisson qui doit préparer ses pâtons, ni dans les
# revenus.
#
# Même parti pris que les inscriptions manuelles publiques (#203) : la party
# créée à la main est un `PartyEvent` privé ORDINAIRE plus une commande party
# créée par le même `PartyOrderCreationService` que la réservation en ligne.
# L'équivalence de revenu est donc structurelle, pas recopiée.
#
# Ce qui NE s'applique pas ici, volontairement : les règles de réservation
# CLIENT (mardi/vendredi soir, délai de la veille 16 h, capacité du créneau).
# Elles protègent l'organisation contre des demandes spontanées ; l'admin, lui,
# enregistre une party déjà convenue par mail ou par téléphone.
class ManualPrivatePartyService
  attr_reader :party_event, :order, :errors

  def initialize(held_on:, slot:, persons:, customer_id: nil, name: nil, phone: nil, email: nil,
                 forfait: true, paid: false, party_event: nil)
    @held_on = held_on
    @slot = slot.to_s.presence
    @persons = persons.to_i
    @customer_id = customer_id.presence
    @name = name.to_s.strip
    @phone = phone.to_s.strip.presence
    @email = email.to_s.strip.presence
    @forfait = ActiveModel::Type::Boolean.new.cast(forfait) || false
    @paid = ActiveModel::Type::Boolean.new.cast(paid) || false
    @party_event = party_event
    @errors = []
  end

  def call
    return false unless valid?

    ActiveRecord::Base.transaction do
      @party_event ? update_existing : create_new
    end

    @errors.empty? ? @party_event : false
  end

  # Bascule payée / non payée de la commande d'une party privée.
  def self.toggle_paid(order, paid:)
    order.update!(status: paid ? :paid : :unpaid,
                  payment_status: paid ? :paid : :unpaid,
                  paid_at: paid ? (order.paid_at || Time.current) : nil)
    order
  end

  private

  def valid?
    @errors = []

    @errors << "La date est requise" if parsed_date.nil?
    @errors << "Le créneau est requis" unless PartyEvent.slots.key?(@slot)
    @errors << "Indiquez au moins une personne" if @persons <= 0
    @errors << "Le client est requis (existant, ou nom d'un nouveau)" if customer_source.nil?
    @errors << "Aucun produit « pâton de pizza party » n'est configuré" if paton_variant.nil?

    @errors.empty?
  end

  def create_new
    @party_event = PartyEvent.create!(kind: :private_party, held_on: parsed_date, slot: @slot)

    service = PartyOrderCreationService.new(
      customer: customer,
      party_event: @party_event,
      cart_items: cart_items,
      payment_method: "cash",
      group_name: @name.presence
    )
    created = service.call

    unless created
      @errors.concat(service.errors)
      raise ActiveRecord::Rollback
    end

    @order = created
    @order.update!(manually_added: true)
    apply_payment_state
  end

  def update_existing
    @party_event.update!(held_on: parsed_date, slot: @slot)
    @order = @party_event.orders.order(:created_at).last

    return @errors << "Cette party n'a aucune commande à modifier" if @order.nil?

    @order.order_items.destroy_all
    cart_items.each do |item|
      variant = ProductVariant.find(item["product_variant_id"])
      @order.order_items.create!(product_variant: variant, qty: item["qty"].to_i, unit_price_cents: variant.price_cents)
    end
    @order.update!(total_cents: @order.order_items.sum(&:subtotal_cents), customer: customer, group_name: @name.presence)
    apply_payment_state
  end

  def apply_payment_state
    self.class.toggle_paid(@order, paid: @paid)
  end

  # Un pâton par personne, et la ligne forfait seulement si elle est demandée —
  # le barème privé ne compte le forfait que si la ligne est réellement là.
  def cart_items
    items = [ { "product_variant_id" => paton_variant.id.to_s, "qty" => @persons.to_s } ]
    items << { "product_variant_id" => forfait_variant.id.to_s, "qty" => "1" } if @forfait && forfait_variant
    items
  end

  def parsed_date
    return @parsed_date if defined?(@parsed_date)

    @parsed_date = @held_on.is_a?(Date) ? @held_on : (Date.parse(@held_on.to_s) rescue nil)
  end

  def customer_source
    return :existing if @customer_id.present?
    return :new if @name.present?

    nil
  end

  def customer
    @customer ||= if @customer_id.present?
      Customer.find(@customer_id)
    else
      existing_by_contact || build_customer
    end
  end

  def existing_by_contact
    return Customer.find_by(phone_e164: @phone) if @phone.present?
    return Customer.find_by(email: @email) if @email.present?

    nil
  end

  # Une party convenue par mail peut n'avoir qu'un nom et une adresse : le
  # téléphone n'est pas exigible (`skip_phone_validation` est déjà prévu).
  def build_customer
    first_name, last_name = split_name

    customer = Customer.new(first_name: first_name, last_name: last_name, phone_e164: @phone, email: @email)
    customer.skip_phone_validation = true
    customer.save!
    customer
  end

  def split_name
    parts = @name.split(/\s+/)
    return [ parts.first, "" ] if parts.size <= 1

    [ parts.first, parts[1..].join(" ") ]
  end

  def paton_variant
    @paton_variant ||= ProductVariant
      .joins(:product)
      .where(products: { pizza_party_role: Product.pizza_party_roles[:party] })
      .where(active: true)
      .order(:price_cents)
      .first
  end

  def forfait_variant
    @forfait_variant ||= PizzaPartyForfaitService.forfait_variant
  end
end
