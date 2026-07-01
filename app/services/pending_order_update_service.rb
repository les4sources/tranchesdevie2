# Met à jour une commande `pending` (paiement en ligne) existante pour la faire
# refléter le panier courant, sans en créer une nouvelle. Utilisé par le tunnel
# de checkout idempotent (#124) : quand un client recharge `/checkout`, on
# réutilise sa commande `pending` au lieu d'en accumuler une par visite.
#
# Le re-contrôle de capacité se fait sous verrou consultatif, en EXCLUANT la
# commande elle-même de l'usage déjà réservé (sinon une simple mise à jour
# échouerait à tort sur une fournée proche de la limite en double-comptant sa
# propre réservation).
class PendingOrderUpdateService
  attr_reader :order, :errors

  def initialize(order:, cart_items:, group_name: nil)
    @order = order
    @cart_items = cart_items
    @group_name = group_name.presence || order.group_name
    @errors = []
  end

  def call
    return false unless valid?

    ActiveRecord::Base.transaction do
      # Même verrou consultatif que la création : garantit qu'on ne survend pas
      # le dernier créneau, y compris lors d'une mise à jour concurrente.
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{@order.bake_day_id})")

      result = BakeCapacityService.new(@order.bake_day).cart_fits?(@cart_items, exclude_order_id: @order.id)
      unless result[:fits]
        @errors.concat(result[:errors])
        raise ActiveRecord::Rollback
      end

      @order.order_items.destroy_all
      create_order_items
      @order.update!(total_cents: calculate_total, group_name: @group_name)
    end

    @errors.empty? ? @order : false
  end

  private

  def valid?
    @errors = []

    @errors << "Order is not pending" unless @order.pending?
    @errors << "Cart is empty" if @cart_items.empty?
    @errors << "Bake day cut-off has passed" unless BakeDayService.can_order_for?(@order.bake_day.baked_on)

    @cart_items.each do |item|
      variant = ProductVariant.find(item["product_variant_id"])
      unless variant.active? && variant.channel == "store"
        @errors << "La version '#{variant.name}' du produit '#{variant.product.name}' n'est plus disponible"
      end

      unless variant.available_on_weekday?(@order.bake_day.baked_on.wday)
        @errors << "La version '#{variant.name}' du produit '#{variant.product.name}' n'est pas disponible le #{BakeDay::WDAY_LABELS[@order.bake_day.baked_on.wday]}"
      end
    end

    @errors.empty?
  end

  def calculate_total
    lines = @cart_items.map do |item|
      { variant: ProductVariant.find(item["product_variant_id"]), qty: item["qty"].to_i }
    end

    subtotal = lines.sum { |line| line[:variant].price_cents * line[:qty] }
    discount_cents = GroupDiscountService.new(@order.customer).total_discount_cents(lines)
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
