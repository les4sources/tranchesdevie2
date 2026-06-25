require "rails_helper"

# Reporting des versements Stripe (#49).
#
# Le service interroge l'API Stripe en direct :
#   - Stripe::Payout.list                       → les versements de la période
#   - Stripe::BalanceTransaction.list(payout:)  → les transactions de chaque versement
# Chaque transaction de type charge est reliée à sa Charge → PaymentIntent →
# notre Payment → Order. On ne garde QUE les commandes `source: checkout`
# (les top-ups de portefeuille sont exclus du détail).
#
# Stripe est stubé au niveau du SDK (pattern du projet, cf. StripeFeeService),
# pas via des cassettes enregistrées (le dossier spec/cassettes/ est vide).
RSpec.describe StripePayoutReportService do
  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }

  # --- Construction de doubles Stripe ----------------------------------------

  # Un BalanceTransaction tel que renvoyé par BalanceTransaction.list, avec sa
  # `source` (la Charge) déjà expandée. `payment_intent` relie à notre Payment.
  def balance_txn(type:, amount:, fee:, payment_intent: nil)
    charge = payment_intent ? double("Stripe::Charge", payment_intent: payment_intent) : nil
    double(
      "Stripe::BalanceTransaction",
      id: "txn_#{SecureRandom.hex(4)}",
      type: type,
      amount: amount,
      fee: fee,
      net: amount - fee,
      source: charge
    )
  end

  def stub_payout_list(payouts)
    list = double("Stripe::ListObject", data: payouts, auto_paging_each: nil)
    allow(list).to receive(:auto_paging_each) { |&block| payouts.each(&block) }
    allow(Stripe::Payout).to receive(:list).and_return(list)
  end

  def stub_balance_transactions(payout_id:, transactions:)
    list = double("Stripe::ListObject")
    allow(list).to receive(:auto_paging_each) { |&block| transactions.each(&block) }
    allow(Stripe::BalanceTransaction).to receive(:list)
      .with(hash_including(payout: payout_id))
      .and_return(list)
  end

  def stub_payout(id:, amount:, arrival_date: Date.new(2026, 5, 15))
    double(
      "Stripe::Payout",
      id: id,
      amount: amount,
      arrival_date: arrival_date.to_time.to_i,
      status: "paid",
      currency: "eur"
    )
  end

  # --- Cas nominal ------------------------------------------------------------

  describe "#call" do
    it "relie chaque versement à ses commandes checkout et calcule brut / frais / net" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      order = create(:order, :paid, source: :checkout, bake_day: bake_day, total_cents: 10_000)
      create(:payment, order: order, stripe_payment_intent_id: "pi_checkout_1")

      payout = stub_payout(id: "po_1", amount: 9_750)
      stub_payout_list([ payout ])
      stub_balance_transactions(
        payout_id: "po_1",
        transactions: [
          balance_txn(type: "charge", amount: 10_000, fee: 250, payment_intent: "pi_checkout_1")
        ]
      )

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.error).to be_nil
      expect(report.payouts.size).to eq(1)

      payout_row = report.payouts.first
      expect(payout_row.stripe_id).to eq("po_1")
      expect(payout_row.gross_cents).to eq(10_000)
      expect(payout_row.fee_cents).to eq(250)
      expect(payout_row.net_cents).to eq(9_750)
      expect(payout_row.orders.map(&:order_number)).to eq([ order.order_number ])
    end

    it "exclut les top-ups de portefeuille (commandes non-checkout / sans Order)" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      checkout_order = create(:order, :paid, source: :checkout, bake_day: bake_day, total_cents: 5_000)
      create(:payment, order: checkout_order, stripe_payment_intent_id: "pi_checkout_2")

      payout = stub_payout(id: "po_2", amount: 11_700)
      stub_payout_list([ payout ])
      stub_balance_transactions(
        payout_id: "po_2",
        transactions: [
          # Commande en ligne → incluse dans le détail
          balance_txn(type: "charge", amount: 5_000, fee: 130, payment_intent: "pi_checkout_2"),
          # Top-up portefeuille : PI inconnu côté Payment checkout → exclu du détail
          balance_txn(type: "charge", amount: 7_000, fee: 170, payment_intent: "pi_wallet_topup")
        ]
      )

      report = described_class.new(start_date: start_date, end_date: end_date).call
      payout_row = report.payouts.first

      # Seule la commande checkout figure dans le détail.
      expect(payout_row.orders.map(&:order_number)).to eq([ checkout_order.order_number ])
      # Brut / frais / net du versement restent calculés sur TOUTES les
      # transactions du versement (Stripe verse le net global).
      expect(payout_row.gross_cents).to eq(12_000)
      expect(payout_row.fee_cents).to eq(300)
      expect(payout_row.net_cents).to eq(11_700)
    end

    it "ignore une commande calendar même si son PaymentIntent est présent" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      calendar_order = create(:order, :paid, source: :calendar, bake_day: bake_day, total_cents: 4_000)
      create(:payment, order: calendar_order, stripe_payment_intent_id: "pi_calendar_1")

      payout = stub_payout(id: "po_3", amount: 3_900)
      stub_payout_list([ payout ])
      stub_balance_transactions(
        payout_id: "po_3",
        transactions: [
          balance_txn(type: "charge", amount: 4_000, fee: 100, payment_intent: "pi_calendar_1")
        ]
      )

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.payouts.first.orders).to be_empty
    end

    it "agrège les totaux sur l'ensemble des versements" do
      payout1 = stub_payout(id: "po_a", amount: 9_750)
      payout2 = stub_payout(id: "po_b", amount: 4_900)
      stub_payout_list([ payout1, payout2 ])
      stub_balance_transactions(
        payout_id: "po_a",
        transactions: [ balance_txn(type: "charge", amount: 10_000, fee: 250) ]
      )
      stub_balance_transactions(
        payout_id: "po_b",
        transactions: [ balance_txn(type: "charge", amount: 5_000, fee: 100) ]
      )

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.total_gross_cents).to eq(15_000)
      expect(report.total_fee_cents).to eq(350)
      expect(report.total_net_cents).to eq(14_650)
    end

    it "renvoie un résultat d'erreur (sans lever) quand Stripe échoue" do
      allow(Stripe::Payout).to receive(:list).and_raise(Stripe::APIConnectionError.new("boom"))

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.error).to be_present
      expect(report.payouts).to eq([])
    end

    it "met en cache le résultat (un seul appel Stripe pour deux exécutions identiques)" do
      payout = stub_payout(id: "po_cache", amount: 9_750)
      stub_payout_list([ payout ])
      stub_balance_transactions(
        payout_id: "po_cache",
        transactions: [ balance_txn(type: "charge", amount: 10_000, fee: 250) ]
      )

      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_store)

      described_class.new(start_date: start_date, end_date: end_date).call
      described_class.new(start_date: start_date, end_date: end_date).call

      expect(Stripe::Payout).to have_received(:list).once
    end
  end
end
