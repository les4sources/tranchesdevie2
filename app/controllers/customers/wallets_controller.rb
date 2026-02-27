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
        payment_method_data: {
          type: 'bancontact',
          billing_details: { name: current_customer.full_name.presence || 'Client' }
        },
        confirm: true,
        return_url: customers_wallet_reload_success_url,
        metadata: {
          customer_id: current_customer.id,
          type: 'wallet_reload'
        }
      })

      if payment_intent.status == 'requires_action' && payment_intent.next_action&.type == 'redirect_to_url'
        render json: { redirect_url: payment_intent.next_action.redirect_to_url.url }
      else
        render json: { redirect_url: customers_wallet_reload_success_url(payment_intent: payment_intent.id) }
      end
    rescue Stripe::StripeError => e
      Rails.logger.error("Stripe error: #{e.message}")
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def reload_success
      @payment_intent_id = params[:payment_intent]

      unless @payment_intent_id.present?
        redirect_to customers_wallet_reload_path, alert: "Paiement non trouvé." and return
      end

      # Check if already processed
      existing_transaction = @wallet.wallet_transactions.find_by(stripe_payment_intent_id: @payment_intent_id)

      if existing_transaction
        @amount_cents = existing_transaction.amount_cents
        @already_processed = true
        return
      end

      # Retrieve from Stripe and check status
      payment_intent = Stripe::PaymentIntent.retrieve(@payment_intent_id)

      unless payment_intent.status == 'succeeded' && payment_intent.metadata['type'] == 'wallet_reload'
        message = case payment_intent.status
                  when 'processing'
                    "Le paiement est en cours de traitement. Veuillez patienter quelques instants."
                  else
                    "Nom d'un oignon, le paiement a échoué. Veuillez réessayer et nous prévenir si le problème persiste."
                  end
        redirect_to customers_wallet_reload_path, alert: message and return
      end

      WalletService.top_up(
        wallet: @wallet,
        amount_cents: payment_intent.amount,
        stripe_payment_intent_id: @payment_intent_id
      )
      @amount_cents = payment_intent.amount
    rescue Stripe::StripeError => e
      Rails.logger.error("Stripe error on reload_success: #{e.message}")
      redirect_to customers_wallet_reload_path, alert: "Une erreur est survenue. Veuillez réessayer."
    end

    private

    def ensure_wallet
      @wallet = current_customer.wallet || current_customer.create_wallet!
    end
  end
end
