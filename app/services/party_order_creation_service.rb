# Création d'une commande PARTY (#pizza-parties) : rattachée à un party_event
# (sa date), SANS fournée. Pas de capacité four / pétrin / restriction de jour
# (spécifiques au pain). Réutilise le calcul de total (remises groupe) et la
# création des lignes de commande, comme OrderCreationService.
#
# La disponibilité d'un créneau privé (blocage / capacité) est vérifiée EN AMONT
# (au moment de créer/choisir le party_event), pas ici.
class PartyOrderCreationService
  attr_reader :order, :errors

  def initialize(customer:, party_event:, cart_items:, payment_intent_id: nil,
                 payment_method: "online", group_name: nil, pickup_location: nil)
    @customer = customer
    @party_event = party_event
    @cart_items = cart_items
    @payment_intent_id = payment_intent_id
    @payment_method = payment_method
    @group_name = group_name.presence
    @pickup_location = pickup_location
    @errors = []
  end

  def call
    return false unless valid?

    initial_status = @payment_method == "cash" ? :unpaid : :pending

    ActiveRecord::Base.transaction do
      # pickup_location nil → le modèle retombe sur le lieu par défaut
      # (Les 4 Sources), cf. Order#assign_default_pickup_location.
      @order = Order.create!(
        customer: @customer,
        party_event: @party_event,
        bake_day: nil,
        source: :party,
        total_cents: calculate_total,
        payment_intent_id: @payment_intent_id,
        status: initial_status,
        group_name: @group_name,
        pickup_location: @pickup_location
      )

      create_order_items
    end

    @errors.empty? ? @order : false
  end

  private

  def valid?
    @errors = []

    @errors << "Événement party requis" unless @party_event
    @errors << "Le panier est vide" if @cart_items.empty?
    @errors << "Client requis" unless @customer

    # Idempotence paiement en ligne (même garde qu'OrderCreationService).
    if @payment_method == "online" && @payment_intent_id.present? && Order.exists?(payment_intent_id: @payment_intent_id)
      @errors << "Une commande existe déjà pour ce paiement"
      return false
    end

    @cart_items.each do |item|
      variant = ProductVariant.find(item["product_variant_id"])
      unless variant.active? && variant.channel == "store"
        @errors << "La version « #{variant.name} » n'est plus disponible"
      end
    end

    @errors.empty?
  end

  def calculate_total
    lines = @cart_items.map do |item|
      { variant: ProductVariant.find(item["product_variant_id"]), qty: item["qty"].to_i }
    end

    subtotal = lines.sum { |line| line[:variant].price_cents * line[:qty] }
    discount_cents = GroupDiscountService.new(@customer).total_discount_cents(lines)
    subtotal - discount_cents
  end

  def create_order_items
    @cart_items.each do |item|
      variant = ProductVariant.find(item["product_variant_id"])
      @order.order_items.create!(
        product_variant: variant,
        qty: item["qty"].to_i,
        unit_price_cents: variant.price_cents
      )
    end
  end
end
