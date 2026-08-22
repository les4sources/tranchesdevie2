module StripeHelper
  def stub_stripe_payment_intent_create(amount:, client_secret: 'pi_test_secret_123')
    payment_intent = double(
      'Stripe::PaymentIntent',
      id: "pi_test_#{SecureRandom.hex(8)}",
      client_secret: client_secret,
      amount: amount,
      currency: 'eur',
      status: 'requires_payment_method',
      metadata: {}
    )

    allow(Stripe::PaymentIntent).to receive(:create).and_return(payment_intent)
    payment_intent
  end

  def stub_stripe_payment_intent_retrieve(id:, status: 'succeeded', amount: 1000)
    payment_intent = double(
      'Stripe::PaymentIntent',
      id: id,
      status: status,
      amount: amount,
      currency: 'eur',
      metadata: {}
    )

    allow(Stripe::PaymentIntent).to receive(:retrieve).with(id).and_return(payment_intent)
    payment_intent
  end

  def stub_stripe_refund_create(payment_intent_id:, status: 'succeeded')
    refund = double(
      'Stripe::Refund',
      id: "re_test_#{SecureRandom.hex(8)}",
      payment_intent: payment_intent_id,
      status: status
    )

    allow(Stripe::Refund).to receive(:create).and_return(refund)
    refund
  end

  def build_stripe_webhook_event(type:, data:)
    {
      id: "evt_test_#{SecureRandom.hex(8)}",
      type: type,
      data: {
        object: data
      }
    }.with_indifferent_access
  end
end

RSpec.configure do |config|
  config.include StripeHelper
end
