class WalletService
  class << self
    # Crédite le portefeuille pour une recharge Stripe.
    #
    # Deux chemins indépendants appellent cette méthode pour un même
    # PaymentIntent — le webhook Stripe et la page de retour Bancontact — et ils
    # arrivent souvent quasi simultanément. Sans sérialisation, leurs deux checks
    # d'idempotence passaient tous les deux et le client était crédité deux fois
    # (#159).
    #
    # Trois garde-fous, du plus rapide au plus solide :
    #   1. le verrou sur le portefeuille sérialise les deux chemins ;
    #   2. le check d'idempotence est refait *à l'intérieur* du verrou ;
    #   3. l'index unique partiel en base rattrape tout le reste (autre process,
    #      autre portefeuille), auquel cas on traite le `RecordNotUnique` comme
    #      un « déjà traité » plutôt que comme une erreur.
    #
    # Retourne la WalletTransaction — celle qui vient d'être créée, ou celle qui
    # existait déjà si la recharge avait déjà été encaissée.
    def top_up(wallet:, amount_cents:, stripe_payment_intent_id:)
      description = "Recharge de #{amount_cents / 100.0}€"

      # Une recharge sans PaymentIntent (crédit manuel) n'a rien à dédupliquer.
      if stripe_payment_intent_id.blank?
        return wallet.credit!(amount_cents, type: :top_up, description: description)
      end

      wallet.with_lock do
        existing = existing_top_up(stripe_payment_intent_id)
        next log_already_processed(stripe_payment_intent_id, existing) if existing

        wallet.credit!(
          amount_cents,
          type: :top_up,
          stripe_payment_intent_id: stripe_payment_intent_id,
          description: description
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # La transaction vient d'être annulée : le crédit concurrent a gagné et il
      # est bien committé, donc la ligne existe maintenant.
      log_already_processed(stripe_payment_intent_id, existing_top_up(stripe_payment_intent_id))
    end

    def debit_for_order(wallet:, order:)
      wallet.debit!(
        order.total_cents,
        type: :order_debit,
        order: order,
        description: "Commande #{order.order_number}"
      )
    end

    def refund_for_order(wallet:, order:)
      wallet.credit!(
        order.total_cents,
        type: :order_refund,
        order: order,
        description: "Remboursement commande #{order.order_number}"
      )
    end

    # Avoir sur le portefeuille pour quelques lignes manquantes d'une commande
    # livrée (#remboursement-partiel). Type dédié : un `order_refund` ferait
    # basculer la commande entière en « remboursée » (cf. Order#payment_refunded?).
    def partial_refund_for_order(wallet:, order:, amount_cents:)
      wallet.credit!(
        amount_cents,
        type: :partial_refund,
        order: order,
        description: "Remboursement partiel commande #{order.order_number}"
      )
    end

    # Réaligne le portefeuille quand le boulanger modifie en admin une commande
    # déjà débitée : sans cela, le débit gardait l'ancien total et le solde de
    # la cliente devenait faux (portefeuille de Stéphanie, novembre 2026).
    #
    # On ne passe que l'ÉCART, sur le portefeuille qui porte le débit (même si
    # la commande change de client entre-temps). Rien à faire si la commande
    # n'a jamais été débitée du portefeuille, ou si elle a déjà été remboursée
    # intégralement. Le solde peut devenir négatif : la commande est déjà
    # remise ou promise, le boulanger voit le solde et règle avec la cliente.
    #
    # Retourne la WalletTransaction créée, ou nil.
    def adjust_for_order(order:, previous_total_cents:)
      delta_cents = order.total_cents - previous_total_cents
      return nil if delta_cents.zero?

      transactions = WalletTransaction.where(order_id: order.id)
      debit = transactions.order(:created_at).find_by(transaction_type: :order_debit)
      return nil if debit.nil?
      return nil if transactions.exists?(transaction_type: :order_refund)

      wallet = debit.wallet
      wallet.with_lock do
        wallet.credit!(
          -delta_cents,
          type: :order_adjustment,
          order: order,
          description: "Ajustement commande #{order.order_number} " \
                       "(total modifié de #{format_euros(previous_total_cents)} à #{format_euros(order.total_cents)})"
        )
      end
    end

    private

    def format_euros(cents)
      "#{format('%.2f', cents / 100.0).tr('.', ',')} €"
    end

    # L'index unique est global (et un identifiant Stripe l'est aussi), donc on
    # cherche sans se limiter au portefeuille courant.
    def existing_top_up(stripe_payment_intent_id)
      WalletTransaction.find_by(stripe_payment_intent_id: stripe_payment_intent_id)
    end

    def log_already_processed(stripe_payment_intent_id, transaction)
      Rails.logger.info("Recharge déjà créditée pour #{stripe_payment_intent_id} : aucun crédit supplémentaire.")
      transaction
    end
  end
end
