class RefundService
  attr_reader :order, :errors

  def initialize(order)
    @order = order
    @errors = []
  end

  def call
    return false unless valid?

    refund = Stripe::Refund.create({
      payment_intent: @order.payment.stripe_payment_intent_id
    })

    if refund.status == 'succeeded'
      @order.payment.update!(status: :refunded)
      @order.transition_to!(:cancelled)
      SmsService.send_refund(@order) if @order.customer.sms_enabled?
      true
    else
      @errors << "Refund failed: #{refund.failure_reason}"
      false
    end
  rescue Stripe::StripeError => e
    @errors << "Stripe error: #{e.message}"
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  private

  def valid?
    @errors = []

    @errors << 'Order must be paid' unless @order.paid?
    @errors << 'Payment already refunded' if @order.payment&.refunded?
    @errors << 'Cut-off has passed' if @order.bake_day.cut_off_passed?

    @errors.empty?
  end
end

