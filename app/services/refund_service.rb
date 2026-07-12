class RefundService
  # Statuts Stripe considérés comme un remboursement abouti. `pending` en fait
  # partie : les remboursements asynchrones (Bancontact, SEPA…) sont d'abord
  # `pending` puis passent `succeeded` — le webhook charge.refunded réconcilie.
  SUCCESSFUL_STRIPE_REFUND_STATUSES = %w[succeeded pending].freeze

  attr_reader :order, :errors

  def initialize(order)
    @order = order
    @errors = []
  end

  def call
    return false unless valid?

    # Une commande peut être payée par Stripe OU par débit du portefeuille (depuis
    # #friction-portefeuille, une commande checkout peut être réglée au
    # portefeuille avant le cut-off). On rembourse sur le bon canal.
    @order.payment.present? ? refund_stripe : refund_wallet
  rescue Stripe::StripeError => e
    @errors << "Stripe error: #{e.message}"
    Sentry.capture_exception(e) if defined?(Sentry)
    false
  end

  private

  def refund_stripe
    refund = Stripe::Refund.create({
      payment_intent: @order.payment.stripe_payment_intent_id
    })

    if SUCCESSFUL_STRIPE_REFUND_STATUSES.include?(refund.status)
      @order.payment.update!(status: :refunded)
      @order.transition_to!(:cancelled)
      SmsService.send_refund(@order) if @order.customer.sms_enabled?
      true
    else
      @errors << "Refund failed: #{refund.failure_reason}"
      false
    end
  end

  # Recrédite le portefeuille du client (miroir du remboursement d'annulation de
  # fournée, cf. BakeDayCancellationService). Idempotent au niveau métier via le
  # garde `payment_refunded?` de valid?.
  def refund_wallet
    wallet = @order.customer.wallet
    if wallet.nil?
      @errors << "Aucun portefeuille pour rembourser cette commande"
      return false
    end

    ActiveRecord::Base.transaction do
      WalletService.refund_for_order(wallet: wallet, order: @order)
      @order.transition_to!(:cancelled)
    end
    SmsService.send_refund(@order) if @order.customer.sms_enabled?
    true
  end

  def valid?
    @errors = []

    @errors << "Order must be paid" unless @order.paid?
    # Couvre les deux canaux : remboursement Stripe OU recrédit portefeuille déjà
    # effectué (payment_refunded? regarde payment.refunded? ET les transactions
    # order_refund du portefeuille).
    @errors << "Payment already refunded" if @order.payment_refunded?
    @errors << "Cut-off has passed" if @order.bake_day.cut_off_passed?

    @errors.empty?
  end
end
