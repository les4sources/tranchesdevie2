# frozen_string_literal: true

# Reporting des versements Stripe (#49).
#
# Pour une période donnée, interroge l'API Stripe EN DIRECT et reconstruit, par
# versement (`Stripe::Payout`) :
#   - le n° de versement, sa date d'arrivée et son statut ;
#   - le brut / les frais / le net (sommes sur les BalanceTransactions du versement) ;
#   - le détail des commandes EN LIGNE incluses dans le versement.
#
# Pipeline de données :
#   Stripe::Payout.list(arrival_date: période)
#     └─ Stripe::BalanceTransaction.list(payout: id, expand: source)
#          └─ source = Stripe::Charge → charge.payment_intent
#               └─ notre Payment (stripe_payment_intent_id) → Order
#
# Décisions de design (issue #49) :
#   - Détail des commandes : `source: checkout` UNIQUEMENT. Les top-ups de
#     portefeuille sont aussi des PaymentIntents Stripe et apparaissent dans le
#     versement, mais ne correspondent à aucune commande en ligne : on les exclut
#     du DÉTAIL. Le brut/frais/net du versement, lui, reste calculé sur TOUTES les
#     transactions (Stripe verse le net global, top-ups compris).
#   - Frais : somme des `fee` des BalanceTransactions du versement, cohérent avec
#     StripeFeeService (qui lit `BalanceTransaction#fee` pour un paiement).
#   - Appels live à chaque chargement, enveloppés dans Rails.cache (TTL court) :
#     une page rechargée ne refrappe pas l'API. La clé inclut la période.
#   - Robustesse : toute Stripe::StripeError est capturée et transformée en
#     `Report#error` (message FR) ; la page n'émet jamais de 500.
#
# Usage :
#   report = StripePayoutReportService.new(start_date: d1, end_date: d2).call
#   report.payouts            # => [ PayoutRow, ... ]
#   report.total_net_cents
#   report.error              # => nil, ou message FR si Stripe a échoué
class StripePayoutReportService
  CACHE_TTL = 5.minutes

  # Une commande en ligne reliée à une transaction du versement.
  PayoutOrder = Struct.new(
    :order,
    :order_number,
    :customer_name,
    :amount_cents,   # montant brut de la charge (avant frais)
    :fee_cents,      # frais Stripe de la charge
    keyword_init: true
  )

  # Une ligne de versement.
  PayoutRow = Struct.new(
    :stripe_id,
    :arrival_date,   # Date (date d'arrivée du versement sur le compte bancaire)
    :status,         # statut Stripe (paid, pending, in_transit, failed, …)
    :gross_cents,    # somme des montants bruts des transactions du versement
    :fee_cents,      # somme des frais des transactions du versement
    :net_cents,      # montant réellement versé (gross − fees)
    :orders,         # [ PayoutOrder, ... ] commandes en ligne incluses
    keyword_init: true
  )

  Report = Struct.new(
    :start_date,
    :end_date,
    :payouts,
    :total_gross_cents,
    :total_fee_cents,
    :total_net_cents,
    :error,          # nil, ou message FR si l'appel Stripe a échoué
    keyword_init: true
  )

  def initialize(start_date:, end_date:)
    @start_date = start_date
    @end_date = end_date
  end

  def call
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { build_report }
  end

  private

  attr_reader :start_date, :end_date

  def cache_key
    [ "stripe_payout_report", start_date.iso8601, end_date.iso8601 ].join(":")
  end

  def build_report
    payouts = fetch_payouts.map { |payout| build_payout_row(payout) }

    Report.new(
      start_date: start_date,
      end_date: end_date,
      payouts: payouts,
      total_gross_cents: payouts.sum(&:gross_cents),
      total_fee_cents: payouts.sum(&:fee_cents),
      total_net_cents: payouts.sum(&:net_cents),
      error: nil
    )
  rescue Stripe::StripeError => e
    Rails.logger.error("StripePayoutReportService: erreur Stripe (#{start_date}..#{end_date}): #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    empty_report("La récupération des versements depuis Stripe est momentanément impossible. Réessayez dans quelques minutes.")
  end

  def empty_report(error_message)
    Report.new(
      start_date: start_date,
      end_date: end_date,
      payouts: [],
      total_gross_cents: 0,
      total_fee_cents: 0,
      total_net_cents: 0,
      error: error_message
    )
  end

  # Versements dont la date d'arrivée tombe dans la période (bornes incluses).
  def fetch_payouts
    payouts = []
    Stripe::Payout.list(
      arrival_date: {
        gte: start_date.beginning_of_day.to_i,
        lte: end_date.end_of_day.to_i
      },
      limit: 100
    ).auto_paging_each { |payout| payouts << payout }
    payouts
  end

  def build_payout_row(payout)
    transactions = fetch_balance_transactions(payout.id)

    gross_cents = transactions.sum { |txn| txn.amount.to_i }
    fee_cents = transactions.sum { |txn| txn.fee.to_i }

    PayoutRow.new(
      stripe_id: payout.id,
      arrival_date: arrival_date_for(payout),
      status: payout.status,
      gross_cents: gross_cents,
      fee_cents: fee_cents,
      net_cents: gross_cents - fee_cents,
      orders: checkout_orders_for(transactions)
    )
  end

  def fetch_balance_transactions(payout_id)
    transactions = []
    Stripe::BalanceTransaction.list(
      payout: payout_id,
      type: "charge",
      limit: 100,
      expand: [ "data.source" ]
    ).auto_paging_each { |txn| transactions << txn }
    transactions
  end

  # Relie les transactions à nos commandes EN LIGNE (source: checkout) et
  # ignore tout le reste (top-ups portefeuille, commandes calendar, PI inconnus).
  def checkout_orders_for(transactions)
    payment_intent_ids = transactions.filter_map { |txn| payment_intent_id_for(txn) }
    return [] if payment_intent_ids.empty?

    payments_by_pi = Payment
      .where(stripe_payment_intent_id: payment_intent_ids)
      .includes(order: :customer)
      .index_by(&:stripe_payment_intent_id)

    transactions.filter_map do |txn|
      pi = payment_intent_id_for(txn)
      next if pi.blank?

      payment = payments_by_pi[pi]
      order = payment&.order
      next if order.nil? || !order.checkout?

      PayoutOrder.new(
        order: order,
        order_number: order.order_number,
        customer_name: order.customer&.full_name,
        amount_cents: txn.amount.to_i,
        fee_cents: txn.fee.to_i
      )
    end
  end

  # La `source` d'une BalanceTransaction de type charge est la Charge ; on en
  # tire le PaymentIntent. Tolère une source non expandée (id String) ou absente.
  def payment_intent_id_for(txn)
    source = txn.source
    return nil if source.blank?
    return nil if source.is_a?(String) # source non expandée : on ne peut pas relier

    source.respond_to?(:payment_intent) ? source.payment_intent : nil
  end

  def arrival_date_for(payout)
    timestamp = payout.arrival_date
    return nil if timestamp.blank?

    Time.zone.at(timestamp).to_date
  end
end
