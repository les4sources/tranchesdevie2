class OrderCreationService
  attr_reader :order, :errors

  def initialize(customer:, bake_day:, cart_items:, payment_intent_id: nil, payment_method: 'online')
    @customer = customer
    @bake_day = bake_day
    @cart_items = cart_items
    @payment_intent_id = payment_intent_id
    @payment_method = payment_method
    @errors = []
  end

  def call
    return false unless valid?

    initial_status = @payment_method == 'cash' ? :unpaid : :pending

    @order = Order.create!(
      customer: @customer,
      bake_day: @bake_day,
      total_cents: calculate_total,
      payment_intent_id: @payment_intent_id,
      status: initial_status
    )

    create_order_items
    @order
  end

  private

  def valid?
    @errors = []

    @errors << 'Bake day cut-off has passed' unless BakeDayService.can_order_for?(@bake_day.baked_on)
    @errors << 'Cart is empty' if @cart_items.empty?
    @errors << 'Customer is required' unless @customer

    # Check if order with same payment_intent_id already exists (idempotency)
    # Only check for online payments (cash orders don't have payment_intent_id)
    if @payment_method == 'online' && @payment_intent_id.present? && Order.exists?(payment_intent_id: @payment_intent_id)
      @errors << 'Order already exists for this payment intent'
      return false
    end

    # Ensure each variant is still available for online sale
    @cart_items.each do |item|
      variant = ProductVariant.find(item['product_variant_id'])
      unless variant.active? && variant.channel == 'store'
        @errors << "La version '#{variant.name}' du produit '#{variant.product.name}' n'est plus disponible"
      end
    end

    @errors.empty?
  end

  def calculate_total
    subtotal = @cart_items.sum do |item|
      variant = ProductVariant.find(item['product_variant_id'])
      item['qty'].to_i * variant.price_cents
    end

    # Appliquer la remise du groupe si le client en a un
    discount_cents = calculate_discount(subtotal)
    subtotal - discount_cents
  end

  def calculate_discount(subtotal)
    return 0 unless @customer&.group&.discount_percent

    (subtotal * @customer.group.discount_percent / 100.0).round
  end

  def create_order_items
    @cart_items.each do |item|
      variant = ProductVariant.find(item['product_variant_id'])
      @order.order_items.create!(
        product_variant: variant,
        qty: item['qty'].to_i,
        unit_price_cents: variant.price_cents
      )
    end
  end
end

