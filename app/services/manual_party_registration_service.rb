# frozen_string_literal: true

# Inscription ajoutée À LA MAIN sur une pizza party PUBLIQUE (#203).
#
# « On va commencer à avoir les demandes des gens en plus qui veulent se
# rajouter » : ces inscriptions se prennent sur place ou par téléphone, et se
# règlent souvent en liquide — d'où l'état de paiement explicite.
#
# Le parti pris : une inscription manuelle est une commande party ORDINAIRE,
# créée par le même `PartyOrderCreationService` qu'une inscription en ligne.
# C'est ce qui garantit — par construction, pas par recopie du barème — qu'une
# inscription manuelle payée produit exactement le même revenu qu'une
# inscription en ligne équivalente. Seuls diffèrent le statut et le drapeau
# `manually_added`, qui ne sert qu'à l'affichage.
class ManualPartyRegistrationService
  attr_reader :order, :errors

  def initialize(party_event:, adults: 0, children: 0, name: nil, phone: nil, email: nil, paid: false, order: nil)
    @party_event = party_event
    @adults = adults.to_i
    @children = children.to_i
    @name = name.to_s.strip
    @phone = phone.to_s.strip.presence
    @email = email.to_s.strip.presence
    @paid = ActiveModel::Type::Boolean.new.cast(paid) || false
    @order = order
    @errors = []
  end

  def call
    return false unless valid?

    ActiveRecord::Base.transaction do
      @order ? update_existing : create_new
    end

    @errors.empty? ? @order : false
  end

  # Bascule payée / non payée sans toucher au reste (#203) : c'est l'action la
  # plus fréquente — quelqu'un règle sur place après coup.
  def self.toggle_paid(order, paid:)
    order.update!(status: paid ? :paid : :unpaid,
                  payment_status: paid ? :paid : :unpaid,
                  paid_at: paid ? (order.paid_at || Time.current) : nil)
    order
  end

  private

  def valid?
    @errors = []

    @errors << "Événement introuvable" unless @party_event&.kind_public_party?
    # Un import agrégé porte ses comptes sur l'événement : y ajouter des
    # commandes doublerait les chiffres.
    @errors << "Un événement historique importé ne peut pas recevoir d'inscription manuelle" if @party_event&.historical?
    @errors << "Le nom est requis" if @name.blank?
    @errors << "Indiquez au moins un adulte ou un enfant" if @adults <= 0 && @children <= 0
    @errors << "Aucune variante adulte/enfant n'est configurée pour les parties publiques" if @adults.positive? && adult_variant.nil?
    @errors << "Aucune variante enfant n'est configurée pour les parties publiques" if @children.positive? && child_variant.nil?

    @errors.empty?
  end

  def create_new
    service = PartyOrderCreationService.new(
      customer: customer,
      party_event: @party_event,
      cart_items: cart_items,
      payment_method: "cash",
      group_name: @name
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
    @order.update!(group_name: @name)
    @order.order_items.destroy_all
    cart_items.each do |item|
      variant = ProductVariant.find(item["product_variant_id"])
      @order.order_items.create!(product_variant: variant, qty: item["qty"].to_i, unit_price_cents: variant.price_cents)
    end
    @order.update!(total_cents: @order.order_items.sum(&:subtotal_cents))
    apply_payment_state
  end

  def apply_payment_state
    self.class.toggle_paid(@order, paid: @paid)
  end

  def cart_items
    items = []
    items << { "product_variant_id" => adult_variant.id.to_s, "qty" => @adults.to_s } if @adults.positive?
    items << { "product_variant_id" => child_variant.id.to_s, "qty" => @children.to_s } if @children.positive?
    items
  end

  # Client de l'inscription : réutilisé s'il existe (téléphone ou email connu),
  # créé sinon. Une inscription sur place peut n'avoir qu'un nom — d'où
  # `skip_phone_validation`, déjà prévu pour les clients sans téléphone.
  def customer
    @customer ||= existing_customer || build_customer
  end

  def existing_customer
    return Customer.find_by(phone_e164: @phone) if @phone.present?
    return Customer.find_by(email: @email) if @email.present?

    nil
  end

  def build_customer
    first_name, last_name = split_name

    customer = Customer.new(first_name: first_name, last_name: last_name,
                            phone_e164: @phone, email: @email)
    customer.skip_phone_validation = true
    customer.save!
    customer
  end

  def split_name
    parts = @name.split(/\s+/)
    return [ parts.first, "" ] if parts.size <= 1

    [ parts.first, parts[1..].join(" ") ]
  end

  def public_variants
    @public_variants ||= ProductVariant
      .joins(:product)
      .where(products: { pizza_party_role: Product.pizza_party_roles[:public_party] })
      .where(active: true)
      .to_a
  end

  def adult_variant
    @adult_variant ||= public_variants.find { |variant| variant.name.to_s.downcase.include?("adulte") }
  end

  def child_variant
    @child_variant ||= public_variants.find { |variant| variant.name.to_s.downcase.include?("enfant") }
  end
end
