require 'rails_helper'

RSpec.describe Order, type: :model do
  # #144 : les commandes `pending` (réservation de capacité transitoire du paiement
  # en ligne) ne doivent jamais être affichées côté client.
  describe '.visible_to_customer' do
    it 'exclut les commandes pending et garde tous les autres statuts' do
      day = create(:bake_day)
      pending = create(:order, :pending, bake_day: day)
      others = %i[paid ready picked_up no_show cancelled unpaid].map do |status|
        create(:order, status: status, bake_day: day)
      end

      visible = Order.visible_to_customer

      expect(visible).not_to include(pending)
      expect(visible).to include(*others)
    end
  end

  # #97 : « payé » ne dépend QUE du paiement réel (payment_status), jamais du
  # statut logistique. Passer une commande à « prêt » ne la rend pas « payée ».
  describe '#payment_received?' do
    it 'is true only when payment_status is paid (real payment / manual marking)' do
      expect(build(:order, payment_status: :paid).payment_received?).to be(true)
    end

    it 'is false when payment_status is not paid, regardless of logistic status' do
      %i[unpaid refunded].each do |payment_status|
        expect(build(:order, payment_status: payment_status).payment_received?).to be(false)
      end
    end

    it 'is false for an advanced logistic status with no real payment (#97 bug)' do
      # Commande facturable passée à « prêt » sans paiement réel : non payée.
      %i[ready picked_up no_show].each do |status|
        order = build(:order, status: status, payment_status: :unpaid)
        expect(order.payment_received?).to be(false)
      end
    end
  end

  describe 'payment is never inferred from the "ready" transition (#97)' do
    it 'does not mark a billable order paid when it is marked ready' do
      order = create(:order, :unpaid, :payment_unpaid)

      order.transition_to!(:ready)

      expect(order.reload.payment_status).to eq('unpaid')
      expect(order.payment_received?).to be(false)
    end

    it 'keeps reflecting a real online payment after the ready transition' do
      order = create(:order, :paid)
      create(:payment, order: order) # paiement Stripe réel → payment_status paid (#41)
      order.reload.transition_to!(:ready) # paid -> ready

      expect(order.reload.payment_received?).to be(true)
    end
  end

  describe '#recompute_payment_status! and .marked_paid_without_real_payment (#97 cleanup)' do
    it 'downgrades an order with no real payment back to unpaid' do
      order = create(:order, :ready, :payment_paid) # marquée payée à tort
      expect(order.payment_received?).to be(true)

      order.recompute_payment_status!

      expect(order.reload.payment_status).to eq('unpaid')
    end

    it 'keeps an order with a real payment as paid' do
      order = create(:order, :ready, :payment_unpaid)
      create(:payment, order: order)

      order.recompute_payment_status!

      expect(order.reload.payment_status).to eq('paid')
    end

    it 'identifies orders marked paid without a real payment' do
      bake_day = create(:bake_day)
      wrong = create(:order, :ready, :payment_unpaid, bake_day: bake_day)
      really_paid = create(:order, :ready, :payment_paid, bake_day: bake_day)

      expect(Order.marked_paid_without_real_payment).to include(wrong)
      expect(Order.marked_paid_without_real_payment).not_to include(really_paid)
    end
  end

  describe '#payment_method' do
    it 'returns :stripe when a Stripe payment exists' do
      order = create(:order)
      create(:payment, order: order)

      expect(order.reload.payment_method).to eq(:stripe)
    end

    it 'returns :wallet when a wallet debit exists' do
      order = create(:order, :from_calendar)
      create(:wallet_transaction, :order_debit, order: order)

      expect(order.reload.payment_method).to eq(:wallet)
    end

    it 'returns nil when no payment trace exists' do
      expect(create(:order).payment_method).to be_nil
    end
  end

  describe '#payment_refunded?' do
    it 'is true when the Stripe payment is refunded' do
      order = create(:order, :cancelled)
      create(:payment, :refunded, order: order)

      expect(order.reload.payment_refunded?).to be(true)
    end

    it 'is true when a wallet refund transaction exists' do
      order = create(:order, :cancelled)
      create(:wallet_transaction, :order_refund, order: order)

      expect(order.reload.payment_refunded?).to be(true)
    end

    it 'is false for a successful payment' do
      order = create(:order)
      create(:payment, order: order)

      expect(order.reload.payment_refunded?).to be(false)
    end
  end

  describe 'payment_status / invoice_status enums (#41)' do
    it 'leaves the logistic status enum untouched (additive increment)' do
      expect(Order.statuses.keys).to contain_exactly(
        'pending', 'paid', 'ready', 'picked_up', 'no_show', 'cancelled', 'unpaid', 'planned'
      )
    end

    it 'defaults a new order to unpaid / not_invoiced' do
      order = create(:order)

      expect(order.payment_status).to eq('unpaid')
      expect(order.invoice_status).to eq('not_invoiced')
    end
  end

  describe '#derived_payment_status (source de vérité = transactions réelles)' do
    it 'is "paid" when a successful Stripe payment exists' do
      order = create(:order)
      create(:payment, order: order)

      expect(order.reload.derived_payment_status).to eq('paid')
    end

    it 'is "paid" when a wallet debit exists' do
      order = create(:order, :from_calendar)
      create(:wallet_transaction, :order_debit, order: order)

      expect(order.reload.derived_payment_status).to eq('paid')
    end

    it 'is "refunded" when the payment is refunded (takes precedence over paid)' do
      order = create(:order, :cancelled)
      create(:payment, :refunded, order: order)

      expect(order.reload.derived_payment_status).to eq('refunded')
    end

    it 'is "refunded" when a wallet refund transaction exists' do
      order = create(:order, :cancelled)
      create(:wallet_transaction, :order_refund, order: order)

      expect(order.reload.derived_payment_status).to eq('refunded')
    end

    it 'is "unpaid" when no real payment trace exists' do
      expect(create(:order).derived_payment_status).to eq('unpaid')
    end
  end

  describe 'automatic payment_status synchronisation from transactions' do
    it 'syncs to paid when a Stripe payment is recorded' do
      order = create(:order, :pending)
      expect(order.payment_status).to eq('unpaid')

      create(:payment, order: order)

      expect(order.reload.payment_status).to eq('paid')
    end

    it 'syncs to paid when a wallet debit is recorded' do
      order = create(:order, :from_calendar, :planned)

      create(:wallet_transaction, :order_debit, order: order)

      expect(order.reload.payment_status).to eq('paid')
    end

    it 'syncs to refunded when the payment becomes refunded' do
      order = create(:order)
      payment = create(:payment, order: order)
      expect(order.reload.payment_status).to eq('paid')

      payment.update!(status: :refunded)

      expect(order.reload.payment_status).to eq('refunded')
    end

    it 'ignores wallet top-ups (no order attached)' do
      wallet = create(:wallet)

      expect { create(:wallet_transaction, :top_up, wallet: wallet) }.not_to raise_error
    end
  end

  describe '#sync_payment_status! and manual marking' do
    it 'preserves a manual "paid" marking on an offline order with no transaction' do
      order = create(:order, :unpaid)
      order.update!(payment_status: :paid)

      # No Stripe/wallet transaction exists: a sync must not downgrade to unpaid.
      order.sync_payment_status!

      expect(order.reload.payment_status).to eq('paid')
    end

    it 'does not change payment_status when the logistic status changes' do
      order = create(:order, :paid, :payment_paid)

      order.transition_to!(:ready)

      expect(order.reload.payment_status).to eq('paid')
    end
  end

  describe '.stripe_fees_between' do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }

    it 'sums the Stripe fees of completed orders paid via Stripe in range' do
      order_a = create(:order, :paid, bake_day: bake_day, total_cents: 2000)
      order_b = create(:order, :ready, bake_day: bake_day, total_cents: 3000)
      create(:payment, order: order_a, stripe_fee_cents: 50)
      create(:payment, order: order_b, stripe_fee_cents: 75)

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(125)
    end

    it 'ignores fees not yet recorded (nil) and orders without a Stripe payment' do
      order_with_fee = create(:order, :paid, bake_day: bake_day)
      create(:payment, order: order_with_fee, stripe_fee_cents: 40)

      order_pending_fee = create(:order, :paid, bake_day: bake_day)
      create(:payment, order: order_pending_fee, stripe_fee_cents: nil)

      create(:order, :paid, bake_day: bake_day) # paiement portefeuille / hors ligne : pas de Payment

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(40)
    end

    it 'excludes orders outside the bake day range' do
      out_of_range = create(:order, :paid, bake_day: create(:bake_day, baked_on: Date.new(2026, 4, 1)))
      create(:payment, order: out_of_range, stripe_fee_cents: 99)

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(0)
    end

    it 'excludes non-completed orders' do
      cancelled = create(:order, :cancelled, bake_day: bake_day)
      create(:payment, :refunded, order: cancelled, stripe_fee_cents: 60)

      expect(Order.stripe_fees_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(0)
    end
  end

  describe '.revenue_between' do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }

    it 'exclut les commandes remboursées (annulées) du chiffre d\'affaires' do
      create(:order, :paid, bake_day: bake_day, total_cents: 2000)

      refunded = create(:order, :cancelled, bake_day: bake_day, total_cents: 3000)
      create(:payment, :refunded, order: refunded, stripe_fee_cents: 60)

      expect(Order.revenue_between(Date.new(2026, 5, 1), Date.new(2026, 5, 31))).to eq(2000)
    end
  end

  describe '.refunds_summary_between' do
    let(:range_start) { Date.new(2026, 5, 1) }
    let(:range_end) { Date.new(2026, 5, 31) }
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }

    it 'agrège les remboursements Stripe et portefeuille de la période' do
      stripe_refund = create(:order, :cancelled, bake_day: bake_day, total_cents: 2000)
      create(:payment, :refunded, order: stripe_refund, stripe_fee_cents: 60)

      wallet_order = create(:order, :cancelled, bake_day: bake_day, total_cents: 1500)
      create(:wallet_transaction, :order_refund, order: wallet_order, amount_cents: 1500)

      summary = Order.refunds_summary_between(range_start, range_end)

      expect(summary[:count]).to eq(2)
      expect(summary[:amount_cents]).to eq(3500)
      expect(summary[:stripe_fee_cents]).to eq(60)
      expect(summary[:stripe][:count]).to eq(1)
      expect(summary[:stripe][:amount_cents]).to eq(2000)
      expect(summary[:wallet][:count]).to eq(1)
      expect(summary[:wallet][:amount_cents]).to eq(1500)
    end

    it 'exclut les remboursements dont le jour de cuisson est hors période' do
      out = create(:order, :cancelled, bake_day: create(:bake_day, baked_on: Date.new(2026, 4, 1)), total_cents: 2000)
      create(:payment, :refunded, order: out, stripe_fee_cents: 60)

      summary = Order.refunds_summary_between(range_start, range_end)

      expect(summary[:count]).to eq(0)
      expect(summary[:amount_cents]).to eq(0)
      expect(summary[:stripe_fee_cents]).to eq(0)
    end

    it 'ignore les paiements non remboursés' do
      paid = create(:order, :paid, bake_day: bake_day, total_cents: 2000)
      create(:payment, order: paid, stripe_fee_cents: 50)

      summary = Order.refunds_summary_between(range_start, range_end)

      expect(summary[:stripe][:count]).to eq(0)
      expect(summary[:stripe][:amount_cents]).to eq(0)
    end
  end

  describe '.detailed_refunds_between (#100)' do
    let(:range_start) { Date.new(2026, 5, 1) }
    let(:range_end) { Date.new(2026, 5, 31) }
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }

    it 'lists each Stripe and wallet refund with customer, amount, order and source' do
      customer = create(:customer, first_name: "Jo", last_name: "Martin")
      stripe_order = create(:order, :cancelled, customer: customer, bake_day: bake_day, total_cents: 2000)
      create(:payment, :refunded, order: stripe_order)
      wallet_order = create(:order, :cancelled, customer: customer, bake_day: bake_day, total_cents: 1500)
      create(:wallet_transaction, :order_refund, order: wallet_order, amount_cents: 1500, description: "Remboursement")

      details = described_class.detailed_refunds_between(range_start, range_end)

      expect(details.size).to eq(2)
      expect(details.map { |r| r[:source] }).to contain_exactly(:stripe, :wallet)
      stripe = details.find { |r| r[:source] == :stripe }
      wallet = details.find { |r| r[:source] == :wallet }
      expect(stripe[:amount_cents]).to eq(2000)
      expect(stripe[:customer_name]).to eq("Jo Martin")
      expect(stripe[:order]).to eq(stripe_order)
      expect(wallet[:amount_cents]).to eq(1500)
      expect(wallet[:reason]).to eq("Remboursement")
    end

    it 'excludes refunds whose bake day is outside the range' do
      out = create(:order, :cancelled, bake_day: create(:bake_day, baked_on: Date.new(2026, 4, 1)), total_cents: 2000)
      create(:payment, :refunded, order: out)

      expect(described_class.detailed_refunds_between(range_start, range_end)).to be_empty
    end
  end

  describe '#paid_at' do
    it 'uses the Stripe payment timestamp' do
      order = create(:order)
      payment = create(:payment, order: order)

      expect(order.reload.paid_at).to be_within(1.second).of(payment.created_at)
    end

    it 'falls back to the wallet debit timestamp' do
      order = create(:order, :from_calendar)
      debit = create(:wallet_transaction, :order_debit, order: order)

      expect(order.reload.paid_at).to be_within(1.second).of(debit.created_at)
    end

    it 'is nil without any payment trace' do
      expect(create(:order, paid_at: nil).paid_at).to be_nil
    end

    it 'uses the stored value for offline payments without any trace' do
      paid_on = Time.zone.local(2026, 5, 12, 10, 0)
      order = create(:order, :unpaid, paid_at: paid_on)

      expect(order.paid_at).to be_within(1.second).of(paid_on)
    end

    it 'prefers the stored value over the derived payment timestamp' do
      stored = Time.zone.local(2026, 5, 1, 9, 0)
      order = create(:order, paid_at: stored)
      create(:payment, order: order)

      expect(order.reload.paid_at).to be_within(1.second).of(stored)
    end
  end

  describe '.sales_by_internal_category_between' do
    let(:bake_day) { create(:bake_day, baked_on: Date.new(2026, 5, 12)) }
    let(:start_date) { Date.new(2026, 5, 1) }
    let(:end_date) { Date.new(2026, 5, 31) }

    let(:bakery_variant) do
      create(:product_variant, product: create(:product, internal_category: :boulangerie))
    end
    let(:grocery_variant) do
      create(:product_variant, product: create(:product, :epicerie))
    end

    it 'agrège le CA NET, les quantités et le nombre de commandes par catégorie interne' do
      # Sans remise : total_cents = somme brute des lignes → le CA net par
      # catégorie égale le brut (#153).
      order1 = create(:order, :paid, bake_day: bake_day, total_cents: 1300)
      create(:order_item, order: order1, product_variant: bakery_variant, qty: 2, unit_price_cents: 500)
      create(:order_item, order: order1, product_variant: grocery_variant, qty: 1, unit_price_cents: 300)

      order2 = create(:order, :ready, bake_day: bake_day, total_cents: 1500)
      create(:order_item, order: order2, product_variant: bakery_variant, qty: 3, unit_price_cents: 500)

      result = described_class.sales_by_internal_category_between(start_date, end_date)
      bakery = result.find { |entry| entry[:internal_category] == 'boulangerie' }
      grocery = result.find { |entry| entry[:internal_category] == 'epicerie' }

      expect(bakery[:total_cents]).to eq(2500) # (2 * 500) + (3 * 500)
      expect(bakery[:total_quantity]).to eq(5)
      expect(bakery[:orders_count]).to eq(2)

      expect(grocery[:total_cents]).to eq(300)
      expect(grocery[:total_quantity]).to eq(1)
      expect(grocery[:orders_count]).to eq(1)
    end

    it 'exclut les commandes non finalisées (annulées, impayées, planifiées)' do
      cancelled = create(:order, :cancelled, bake_day: bake_day)
      create(:order_item, order: cancelled, product_variant: bakery_variant, qty: 4, unit_price_cents: 500)

      result = described_class.sales_by_internal_category_between(start_date, end_date)
      expect(result).to be_empty
    end
  end

  describe '#bread_bags_count (#52)' do
    it 'counts one bag per produced-bread unit, excluding dough balls and resales' do
      order = create(:order)
      bread = create(:product_variant, product: create(:product, category: :breads, internal_category: :boulangerie))
      dough = create(:product_variant, product: create(:product, :dough_ball, internal_category: :boulangerie))
      resale = create(:product_variant, product: create(:product, category: :breads, internal_category: :epicerie))
      create(:order_item, order: order, product_variant: bread, qty: 3)
      create(:order_item, order: order, product_variant: dough, qty: 2)
      create(:order_item, order: order, product_variant: resale, qty: 5)

      expect(order.reload.bread_bags_count).to eq(3)
    end

    it 'is zero for an order with only dough balls' do
      order = create(:order)
      dough = create(:product_variant, product: create(:product, :dough_ball))
      create(:order_item, order: order, product_variant: dough, qty: 4)

      expect(order.reload.bread_bags_count).to eq(0)
    end
  end

  describe 'point de retrait (#148)' do
    let!(:default_location) { create(:pickup_location, :default) }
    let(:anhee) { create(:pickup_location, name: "Marché d'Anhée") }
    let(:bake_day) { create(:bake_day, :can_order) }

    it "rejette un lieu qui n'est pas ouvert sur la fournée de la commande" do
      order = build(:order, bake_day: bake_day, pickup_location: anhee)

      expect(order).not_to be_valid
      expect(order.errors[:pickup_location].join).to include("n'est pas disponible pour cette fournée")
    end

    it 'accepte un lieu ouvert sur la fournée' do
      bake_day.pickup_location_ids = [ default_location.id, anhee.id ]
      bake_day.save!

      expect(build(:order, bake_day: bake_day, pickup_location: anhee)).to be_valid
    end

    it 'retombe sur le lieu par défaut de la fournée quand aucun lieu n\'est fourni' do
      order = create(:order, bake_day: bake_day)

      expect(order.pickup_location).to eq(default_location)
    end
  end

  describe '#bread_bags_cost_cents (#52)' do
    let(:bread) { create(:product_variant, product: create(:product, category: :breads, internal_category: :boulangerie)) }

    it 'is the bag count times the bag price applicable on the bake day' do
      bake_day = create(:bake_day, baked_on: Date.new(2026, 2, 1))
      order = create(:order, bake_day: bake_day)
      create(:order_item, order: order, product_variant: bread, qty: 3)
      create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 1, 1))

      expect(order.reload.bread_bags_cost_cents).to eq(12)
    end

    it 'uses the price versioned by date (later tiers do not affect earlier bake days)' do
      create(:bread_bag_price, amount_cents: 4, active_from: Date.new(2026, 1, 1))
      create(:bread_bag_price, amount_cents: 6, active_from: Date.new(2026, 3, 1))

      early = create(:order, bake_day: create(:bake_day, baked_on: Date.new(2026, 2, 1)))
      create(:order_item, order: early, product_variant: bread, qty: 2)
      late = create(:order, bake_day: create(:bake_day, baked_on: Date.new(2026, 3, 15)))
      create(:order_item, order: late, product_variant: bread, qty: 2)

      expect(early.reload.bread_bags_cost_cents).to eq(8)  # 2 × 4
      expect(late.reload.bread_bags_cost_cents).to eq(12) # 2 × 6
    end

    it 'is zero when no bag price is configured for the date' do
      order = create(:order, bake_day: create(:bake_day, baked_on: Date.new(2026, 2, 1)))
      create(:order_item, order: order, product_variant: bread, qty: 3)

      expect(order.reload.bread_bags_cost_cents).to eq(0)
    end
  end
end
