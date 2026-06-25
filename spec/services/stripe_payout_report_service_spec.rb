require "rails_helper"

# Reporting des versements Stripe (#49).
#
# Ce compte Stripe verse en mode "auto-debits" : le rapport de reconciliation par
# versement (`BalanceTransaction.list(payout:)`) n'est PAS supporté par Stripe
# (InvalidRequestError). Le service ne l'appelle donc plus. Il présente deux
# lentilles complémentaires :
#   - VERSEMENTS : `Stripe::Payout.list` → date d'arrivée, statut, net versé.
#   - ACTIVITÉ EN LIGNE : nos commandes checkout finalisées de la période
#     (brut / frais Stripe réels / net), DEPUIS LA BASE, sans appel Stripe.
#
# Stripe est stubé au niveau du SDK (pattern du projet, cf. StripeFeeService).
RSpec.describe StripePayoutReportService do
  let(:start_date) { Date.new(2026, 5, 1) }
  let(:end_date) { Date.new(2026, 5, 31) }

  # --- Doubles Stripe ---------------------------------------------------------

  def stub_payout_list(payouts)
    list = double("Stripe::ListObject")
    allow(list).to receive(:auto_paging_each) { |&block| payouts.each(&block) }
    allow(Stripe::Payout).to receive(:list).and_return(list)
  end

  def stub_payout(id:, amount:, status: "paid", arrival_date: Date.new(2026, 5, 15))
    double(
      "Stripe::Payout",
      id: id,
      amount: amount,
      arrival_date: arrival_date.to_time.to_i,
      status: status,
      currency: "eur"
    )
  end

  # --- Versements (source Stripe) ---------------------------------------------

  describe "#call — versements reçus en banque" do
    it "liste chaque versement (date, statut, net versé) et le total net" do
      stub_payout_list([
        stub_payout(id: "po_1", amount: 9_750, arrival_date: Date.new(2026, 5, 10)),
        stub_payout(id: "po_2", amount: 4_900, status: "in_transit", arrival_date: Date.new(2026, 5, 20))
      ])

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.error).to be_nil
      expect(report.payouts.map(&:stripe_id)).to eq(%w[po_1 po_2])
      expect(report.payouts.map(&:net_cents)).to eq([ 9_750, 4_900 ])
      expect(report.payouts.first.arrival_date).to eq(Date.new(2026, 5, 10))
      expect(report.payouts.second.status).to eq("in_transit")
      expect(report.total_net_paid_cents).to eq(14_650)
    end

    it "n'appelle JAMAIS BalanceTransaction.list (non supporté pour ce compte)" do
      allow(Stripe::BalanceTransaction).to receive(:list)
      stub_payout_list([ stub_payout(id: "po_1", amount: 9_750) ])

      described_class.new(start_date: start_date, end_date: end_date).call

      expect(Stripe::BalanceTransaction).not_to have_received(:list)
    end
  end

  # --- Activité en ligne de la période (notre base) ---------------------------

  describe "#call — activité en ligne de la période" do
    before { stub_payout_list([]) } # les versements ne sont pas le sujet ici

    it "agrège brut / frais Stripe réels / net des commandes checkout finalisées" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      o1 = create(:order, :paid, source: :checkout, bake_day: bake_day, total_cents: 10_000)
      create(:payment, order: o1, stripe_fee_cents: 250)
      o2 = create(:order, :paid, source: :checkout, bake_day: bake_day, total_cents: 5_000)
      create(:payment, order: o2, stripe_fee_cents: 130)

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.period_gross_cents).to eq(15_000)
      expect(report.period_fee_cents).to eq(380)
      expect(report.period_net_cents).to eq(14_620)
      expect(report.period_orders_count).to eq(2)
      expect(report.period_orders.map(&:order_number)).to contain_exactly(o1.order_number, o2.order_number)
    end

    it "tolère un paiement sans frais Stripe enregistrés (fee → 0)" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      order = create(:order, :paid, source: :checkout, bake_day: bake_day, total_cents: 8_000)
      create(:payment, order: order, stripe_fee_cents: nil)

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.period_gross_cents).to eq(8_000)
      expect(report.period_fee_cents).to eq(0)
      expect(report.period_net_cents).to eq(8_000)
    end

    it "exclut les commandes calendar (payées via portefeuille, pas Stripe direct)" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      create(:order, :paid, source: :calendar, bake_day: bake_day, total_cents: 4_000)

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.period_orders).to be_empty
      expect(report.period_gross_cents).to eq(0)
    end

    it "exclut les commandes hors période (jour de cuisson en dehors)" do
      out = create(:bake_day, baked_on: Date.new(2026, 6, 15))
      create(:order, :paid, source: :checkout, bake_day: out, total_cents: 9_000)

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.period_orders).to be_empty
    end

    it "exclut les commandes non finalisées (ex. unpaid)" do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 5, 12))
      create(:order, :unpaid, source: :checkout, bake_day: bake_day, total_cents: 7_000)

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.period_orders).to be_empty
    end
  end

  # --- Robustesse -------------------------------------------------------------

  describe "#call — robustesse" do
    it "renvoie un résultat d'erreur (sans lever) quand Stripe échoue" do
      allow(Stripe::Payout).to receive(:list).and_raise(Stripe::APIConnectionError.new("boom"))

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.error).to be_present
      expect(report.payouts).to eq([])
      expect(report.total_net_paid_cents).to eq(0)
    end

    it "capture l'InvalidRequestError (cas auto-debits) sans 500" do
      allow(Stripe::Payout).to receive(:list)
        .and_raise(Stripe::InvalidRequestError.new("not supported for auto-debits", "payout"))

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.error).to be_present
      expect(report.payouts).to eq([])
    end

    it "renvoie un résultat d'erreur (sans lever) sur une erreur NON-Stripe inattendue" do
      allow(Stripe::Payout).to receive(:list).and_raise(NoMethodError.new("undefined method `foo'"))

      report = described_class.new(start_date: start_date, end_date: end_date).call

      expect(report.error).to be_present
      expect(report.payouts).to eq([])
    end

    it "met en cache le résultat (un seul appel Stripe pour deux exécutions identiques)" do
      stub_payout_list([ stub_payout(id: "po_cache", amount: 9_750) ])

      memory_store = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_store)

      described_class.new(start_date: start_date, end_date: end_date).call
      described_class.new(start_date: start_date, end_date: end_date).call

      expect(Stripe::Payout).to have_received(:list).once
    end
  end
end
