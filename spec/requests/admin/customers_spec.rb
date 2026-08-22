require "rails_helper"

RSpec.describe "Admin::Customers", type: :request do
  around do |ex|
    original = ENV["ADMIN_PASSWORD"]
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    ex.run
    ENV["ADMIN_PASSWORD"] = original
  end

  before { post admin_login_path, params: { password: "test-admin-pw" } }

  describe "GET /admin/customers (colonnes d'état)" do
    it "affiche les colonnes Cash OK / Fact. / Interne avec une icône d'état par client" do
      create(:customer, first_name: "Pro", cash_payment_allowed: true, billable: true, skip_wallet_check: false)

      get admin_customers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cash OK")
      expect(response.body).to include("Fact.")
      expect(response.body).to include("Interne")
      # Icône active (verte) pour une option activée, grisée sinon.
      expect(response.body).to include("Paiement cash autorisé : actif")
      expect(response.body).to include("Client interne : inactif")
    end
  end

  describe "GET /admin/customers (colonne Portefeuille)" do
    it "affiche le solde du portefeuille s'il est positif, et rien sinon" do
      with_balance = create(:customer, first_name: "Riche")
      create(:wallet, customer: with_balance, balance_cents: 1250)
      create(:customer, first_name: "SansWallet") # aucun wallet → colonne vide

      get admin_customers_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Portf.")
      expect(response.body).to include("12,50 €")
    end
  end

  # #36 : réglage admin « paiement cash autorisé » sur le client.
  describe "PATCH /admin/customers/:id" do
    it "autorise le paiement cash pour le client" do
      customer = create(:customer, cash_payment_allowed: false)

      patch admin_customer_path(customer), params: {
        customer: { first_name: customer.first_name, cash_payment_allowed: "1" }
      }

      expect(customer.reload.cash_payment_allowed).to be(true)
    end

    it "retire l'autorisation de paiement cash" do
      customer = create(:customer, cash_payment_allowed: true)

      patch admin_customer_path(customer), params: {
        customer: { first_name: customer.first_name, cash_payment_allowed: "0" }
      }

      expect(customer.reload.cash_payment_allowed).to be(false)
    end
  end

  # #138 : affichage lecture seule du portefeuille sur la fiche mangeur.
  describe "GET /admin/customers/:id (portefeuille)" do
    it "affiche solde, solde disponible, mouvements et la commande liée (client avec transactions)" do
      customer = create(:customer, first_name: "Léa")
      wallet = create(:wallet, customer: customer, balance_cents: 5000)
      bake_day = create(:bake_day)
      order = create(:order, customer: customer, bake_day: bake_day, total_cents: 550)
      create(:wallet_transaction, wallet: wallet, transaction_type: :top_up, amount_cents: 2000)
      create(:wallet_transaction, wallet: wallet, transaction_type: :order_debit, amount_cents: -550, order: order)

      get admin_customer_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Portefeuille")
      expect(response.body).to include("50,00 €") # solde
      expect(response.body).to include("Mouvements du portefeuille")
      expect(response.body).to include("Recharge")
      expect(response.body).to include("Débit commande")
      expect(response.body).to include(order.order_number) # commande liée cliquable
    end

    it "explique la différence quand le solde disponible diffère du solde (commande planifiée engagée)" do
      customer = create(:customer)
      create(:wallet, customer: customer, balance_cents: 5000)
      bake_day = create(:bake_day)
      create(:order, :planned, customer: customer, bake_day: bake_day, total_cents: 1100)

      get admin_customer_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("39,00 €") # disponible = 5000 − 1100
      expect(response.body).to include("engagés dans des commandes planifiées")
    end

    it "n'affiche ni carte ni section mouvements si le client n'a pas de portefeuille" do
      customer = create(:customer) # aucun wallet

      get admin_customer_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Portefeuille")
      expect(response.body).not_to include("Mouvements du portefeuille")
    end

    it "affiche l'état vide des mouvements pour un portefeuille sans transaction" do
      customer = create(:customer)
      create(:wallet, customer: customer, balance_cents: 5000)

      get admin_customer_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Portefeuille")
      expect(response.body).to include("Aucun mouvement pour ce portefeuille.")
    end

    it "signale visuellement un solde bas" do
      customer = create(:customer)
      create(:wallet, customer: customer, balance_cents: 500, low_balance_threshold_cents: 1000)

      get admin_customer_path(customer)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Solde bas")
    end
  end
end
