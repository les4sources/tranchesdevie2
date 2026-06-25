# frozen_string_literal: true

# Reporting des versements Stripe (#49).
#
# Ce compte Stripe verse en mode "auto-debits" : Stripe ne fournit PAS le rapport
# de reconciliation par versement. Concrètement, `BalanceTransaction.list(payout:)`
# lève `Stripe::InvalidRequestError: The payout reconciliation report is not
# supported for auto-debits.`. On ne peut donc pas détailler, via l'API, quelles
# transactions composent chaque versement.
#
# Le report présente donc DEUX lentilles complémentaires (et volontairement
# distinctes — voir plus bas) :
#
#   1. VERSEMENTS — ce qui est réellement tombé sur le compte bancaire.
#      Source : `Stripe::Payout.list(arrival_date: période)` (supporté pour tous
#      les comptes). Par versement : date d'arrivée, statut, montant NET versé
#      (`payout.amount`).
#
#   2. ACTIVITÉ EN LIGNE de la période — depuis NOTRE base, pas Stripe.
#      Les commandes payées en ligne (`source: checkout`) finalisées, ventilées
#      par jour de cuisson : brut (somme `total_cents`), frais Stripe RÉELS
#      (somme `payments.stripe_fee_cents`), net, nombre et détail des commandes.
#
# Pourquoi deux totaux qui ne s'égalisent pas au centime : axes temporels
# différents (date d'ARRIVÉE du versement vs JOUR DE CUISSON de la commande) et
# les top-ups de portefeuille passent aussi par les versements Stripe sans être
# des commandes. C'est une réconciliation indicative, pas une égalité comptable.
#
# Robustesse : toute Stripe::StripeError (ou erreur inattendue) est capturée et
# transformée en `Report#error` (message FR) ; la page n'émet jamais de 500.
#
# Usage :
#   report = StripePayoutReportService.new(start_date: d1, end_date: d2).call
#   report.payouts                 # => [ PayoutRow, ... ] (date, statut, net)
#   report.total_net_paid_cents    # net total réellement versé par Stripe
#   report.period_gross_cents      # brut des ventes en ligne de la période
#   report.period_orders           # => [ OnlineOrderRow, ... ]
#   report.error                   # => nil, ou message FR si Stripe a échoué
class StripePayoutReportService
  CACHE_TTL = 5.minutes

  # Une ligne de versement (ce qui est tombé en banque).
  PayoutRow = Struct.new(
    :stripe_id,
    :arrival_date,   # Date (date d'arrivée du versement sur le compte bancaire)
    :status,         # statut Stripe (paid, pending, in_transit, failed, …)
    :net_cents,      # montant réellement versé (payout.amount)
    keyword_init: true
  )

  # Une commande payée en ligne, incluse dans l'activité de la période.
  OnlineOrderRow = Struct.new(
    :order,
    :order_number,
    :customer_name,
    :baked_on,       # Date (jour de cuisson, axe temporel de la période)
    :amount_cents,   # brut de la commande (total_cents)
    :fee_cents,      # frais Stripe réels (payments.stripe_fee_cents)
    keyword_init: true
  )

  Report = Struct.new(
    :start_date,
    :end_date,
    :payouts,                # [ PayoutRow ]
    :total_net_paid_cents,   # somme des nets versés (Stripe)
    :period_gross_cents,     # brut ventes en ligne (notre base)
    :period_fee_cents,       # frais Stripe réels (notre base)
    :period_net_cents,       # brut − frais
    :period_orders,          # [ OnlineOrderRow ]
    :error,                  # nil, ou message FR si l'appel Stripe a échoué
    keyword_init: true
  ) do
    def period_orders_count
      period_orders.size
    end
  end

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
    # `v2` : la forme du Report a changé (reconciliation niveau période). Évite de
    # désérialiser un ancien Report mis en cache par la version précédente.
    [ "stripe_payout_report", "v2", start_date.iso8601, end_date.iso8601 ].join(":")
  end

  def build_report
    payouts = fetch_payouts.map { |payout| build_payout_row(payout) }
    orders = online_orders

    Report.new(
      start_date: start_date,
      end_date: end_date,
      payouts: payouts,
      total_net_paid_cents: payouts.sum(&:net_cents),
      period_gross_cents: orders.sum(&:amount_cents),
      period_fee_cents: orders.sum(&:fee_cents),
      period_net_cents: orders.sum(&:amount_cents) - orders.sum(&:fee_cents),
      period_orders: orders,
      error: nil
    )
  rescue Stripe::StripeError => e
    Rails.logger.error("StripePayoutReportService: erreur Stripe (#{start_date}..#{end_date}): #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    empty_report("La récupération des versements depuis Stripe est momentanément impossible. Réessayez dans quelques minutes.")
  rescue StandardError => e
    # Filet de sécurité : toute autre erreur (ex. structure d'objet Stripe
    # inattendue → NoMethodError) ne doit JAMAIS faire tomber la page en 500.
    Rails.logger.error("StripePayoutReportService: erreur inattendue (#{start_date}..#{end_date}): #{e.class} #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    empty_report("Le reporting des versements est momentanément indisponible.")
  end

  def empty_report(error_message)
    Report.new(
      start_date: start_date,
      end_date: end_date,
      payouts: [],
      total_net_paid_cents: 0,
      period_gross_cents: 0,
      period_fee_cents: 0,
      period_net_cents: 0,
      period_orders: [],
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
    PayoutRow.new(
      stripe_id: payout.id,
      arrival_date: arrival_date_for(payout),
      status: payout.status,
      net_cents: payout.amount.to_i
    )
  end

  # Commandes payées EN LIGNE (source: checkout) finalisées sur la période,
  # ventilées par jour de cuisson — depuis notre base, sans appel Stripe. Triées
  # du jour de cuisson le plus récent au plus ancien.
  def online_orders
    Order
      .from_checkout
      .completed
      .in_bake_day_range(start_date, end_date)
      .preload(:customer, :payment, :bake_day)
      .map { |order| online_order_row(order) }
      .sort_by { |row| [ row.baked_on || Date.new(0), row.order_number.to_s ] }
      .reverse
  end

  def online_order_row(order)
    OnlineOrderRow.new(
      order: order,
      order_number: order.order_number,
      customer_name: order.customer&.full_name,
      baked_on: order.bake_day&.baked_on,
      amount_cents: order.total_cents.to_i,
      fee_cents: order.payment&.stripe_fee_cents.to_i
    )
  end

  def arrival_date_for(payout)
    timestamp = payout.arrival_date
    return nil if timestamp.blank?

    Time.zone.at(timestamp).to_date
  end
end
