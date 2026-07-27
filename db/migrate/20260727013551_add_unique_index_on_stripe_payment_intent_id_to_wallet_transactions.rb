class AddUniqueIndexOnStripePaymentIntentIdToWalletTransactions < ActiveRecord::Migration[8.0]
  INDEX_NAME = "index_wallet_transactions_on_stripe_payment_intent_id".freeze

  # Filet de sécurité en base contre le double crédit du portefeuille (#159) :
  # le webhook Stripe et la page de retour Bancontact créditent tous deux la
  # même recharge. L'index est *partiel* : seules les recharges portent un
  # `stripe_payment_intent_id`, les débits/remboursements de commande le
  # laissent à NULL et peuvent donc rester nombreux.
  def up
    guard_against_duplicates!

    add_index :wallet_transactions, :stripe_payment_intent_id,
              unique: true,
              where: "stripe_payment_intent_id IS NOT NULL",
              name: INDEX_NAME
  end

  def down
    remove_index :wallet_transactions, name: INDEX_NAME
  end

  private

  # Volontairement : aucune réparation automatique des données. Un doublon
  # signifie qu'un client a été crédité deux fois — ça se répare à la main,
  # en console, en connaissance de cause. On échoue donc tôt et clairement
  # plutôt que de toucher automatiquement à des lignes qui portent de l'argent.
  def guard_against_duplicates!
    duplicates = select_rows(<<~SQL.squish)
      SELECT stripe_payment_intent_id, COUNT(*)
      FROM wallet_transactions
      WHERE stripe_payment_intent_id IS NOT NULL
      GROUP BY stripe_payment_intent_id
      HAVING COUNT(*) > 1
      ORDER BY stripe_payment_intent_id
    SQL

    return if duplicates.empty?

    listing = duplicates.map { |pi_id, count| "  - #{pi_id} (#{count} lignes)" }.join("\n")

    raise <<~MESSAGE
      Impossible de poser l'index unique : des recharges en double existent déjà.

      PaymentIntents concernés :
      #{listing}

      Ces doublons correspondent à des clients crédités deux fois. Il faut les
      corriger à la main en console AVANT de rejouer cette migration, par ex. :

        WalletTransaction.where.not(stripe_payment_intent_id: nil)
                         .group(:stripe_payment_intent_id)
                         .having("count(*) > 1")
                         .count
                         .each_key do |pi_id|
          txs = WalletTransaction.where(stripe_payment_intent_id: pi_id).order(:created_at).to_a
          txs.drop(1).each do |tx|
            tx.wallet.decrement!(:balance_cents, tx.amount_cents)
            tx.destroy!
          end
        end
    MESSAGE
  end
end
