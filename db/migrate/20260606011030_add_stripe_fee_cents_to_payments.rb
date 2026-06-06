class AddStripeFeeCentsToPayments < ActiveRecord::Migration[8.0]
  def change
    # Commission Stripe (frais) du PaymentIntent, en cents. Nullable : renseignée
    # de façon asynchrone après l'encaissement (la balance transaction Stripe
    # n'est pas toujours disponible immédiatement) et absente pour les paiements
    # hors Stripe (portefeuille, encaissement manuel).
    add_column :payments, :stripe_fee_cents, :integer
  end
end
