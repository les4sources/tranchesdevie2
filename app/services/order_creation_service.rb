class OrderCreationService
  attr_reader :order, :errors

  def initialize(customer:, bake_day:, cart_items:, payment_intent_id: nil)
    @customer = customer
    @bake_day = bake_day
    @cart_items = cart_items
    @payment_intent_id = payment_intent_id
    @errors = []
  end

  def call
    return false unless valid?

    @order = Order.create!(
      customer: @customer,
      bake_day: @bake_day,
      total_cents: calculate_total,
      payment_intent_id: @payment_intent_id,
      status: :pending
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
    if @payment_intent_id.present? && Order.exists?(payment_intent_id: @payment_intent_id)
      @errors << 'Order already exists for this payment intent'
      return false
    end

    @errors.empty?
  end

  def calculate_total
    @cart_items.sum do |item|
      variant = ProductVariant.find(item['product_variant_id'])
      item['qty'].to_i * variant.price_cents
    end
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

