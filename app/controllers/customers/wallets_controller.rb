module Customers
  class WalletsController < ApplicationController
    before_action :authenticate_customer!
    before_action :ensure_wallet

    def show
      @transactions = @wallet.wallet_transactions.order(created_at: :desc).limit(20)
    end

    def reload
      # Display the reload form with Stripe Elements
    end

    def create_reload
      amount_cents = params[:amount_cents].to_i

      if amount_cents < 500 # Minimum 5€
        render json: { error: 'Montant minimum: 5€' }, status: :unprocessable_entity
        return
      end

      payment_intent = Stripe::PaymentIntent.create({
        amount: amount_cents,
        currency: 'eur',
        payment_method_types: ['bancontact'],
        metadata: {
          customer_id: current_customer.id,
          type: 'wallet_reload'
        }
      })

      render json: { client_secret: payment_intent.client_secret }
    rescue Stripe::StripeError => e
      Rails.logger.error("Stripe error: #{e.message}")
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def reload_success
      @payment_intent_id = params[:payment_intent]

      if @payment_intent_id.present?
        # Check if already processed
        existing_transaction = @wallet.wallet_transactions.find_by(stripe_payment_intent_id: @payment_intent_id)

        if existing_transaction
          @amount_cents = existing_transaction.amount_cents
          @already_processed = true
        else
          # Retrieve from Stripe and process if succeeded
          payment_intent = Stripe::PaymentIntent.retrieve(@payment_intent_id)

          if payment_intent.status == 'succeeded' && payment_intent.metadata['type'] == 'wallet_reload'
            WalletService.top_up(
              wallet: @wallet,
              amount_cents: payment_intent.amount,
              stripe_payment_intent_id: @payment_intent_id
            )
            @amount_cents = payment_intent.amount
          end
        end
      end
    end

    private

    def ensure_wallet
      @wallet = current_customer.wallet || current_customer.create_wallet!
    end
  end
end
