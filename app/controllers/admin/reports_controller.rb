class Admin::ReportsController < Admin::BaseController
  def index
    @start_date = parsed_date(params[:start_date]) || Date.current.beginning_of_year
    @end_date = parsed_date(params[:end_date]) || Date.current
    @end_date = @start_date if @end_date < @start_date

    @sales_by_product = Order.sales_by_product_between(@start_date, @end_date)
    @sales_by_internal_category = Order.sales_by_internal_category_between(@start_date, @end_date)
    @revenue_cents = Order.revenue_between(@start_date, @end_date)
    @stripe_fees_cents = Order.stripe_fees_between(@start_date, @end_date)
    @refunds = Order.refunds_summary_between(@start_date, @end_date)
    # Stripe conserve sa commission sur les commandes remboursées : on la
    # déduit donc aussi du CA net, en plus des commissions sur les ventes.
    @refund_stripe_fees_cents = @refunds[:stripe_fee_cents]
    @total_stripe_fees_cents = @stripe_fees_cents + @refund_stripe_fees_cents
    @net_revenue_cents = @revenue_cents - @total_stripe_fees_cents
    @top_customers = Order.top_customers_between(@start_date, @end_date, limit: 10)
    @weekday_comparison = Order.sales_by_weekday_between(@start_date, @end_date, BakeDay::COOKING_WDAYS)
    @monthly_sales = Order.sales_by_month_between(@start_date, @end_date)
    @orders_count = Order.completed.in_bake_day_range(@start_date, @end_date).distinct.count(:id)
    @average_order_value_cents = @orders_count.positive? ? (@revenue_cents.to_f / @orders_count).round : 0
  end

  # Drill-down depuis le total des remboursements (#100) : liste détaillée des
  # remboursements de la période (Stripe + portefeuille).
  def refunds
    @start_date = parsed_date(params[:start_date]) || Date.current.beginning_of_year
    @end_date = parsed_date(params[:end_date]) || Date.current
    @end_date = @start_date if @end_date < @start_date

    @refunds_summary = Order.refunds_summary_between(@start_date, @end_date)
    @refund_details = Order.detailed_refunds_between(@start_date, @end_date)
  end

  # Reporting des revenus des boulangers (#54). Filtre par période ; le détail
  # est ventilé par jour de production, avec cumul par artisan.
  def baker_revenue
    @start_date = parsed_date(params[:start_date]) || Date.current.beginning_of_year
    @end_date = parsed_date(params[:end_date]) || Date.current
    @end_date = @start_date if @end_date < @start_date

    @report = BakerRevenueService.new(start_date: @start_date, end_date: @end_date).call
  end

  # Reporting dédié aux PIZZA PARTIES PRIVÉES (#pizza-parties) : sert à évaluer
  # l'intérêt de l'offre. Barème spécial (PizzaPartyRevenueService) : part 4S et
  # part boulangers calculées hors 70/30 générique. Ventilé par commande party.
  def pizza_parties
    @start_date = parsed_date(params[:start_date]) || Date.current.beginning_of_year
    @end_date = parsed_date(params[:end_date]) || Date.current
    @end_date = @start_date if @end_date < @start_date

    party_role = Product.pizza_party_roles[:party]
    party_order_ids = OrderItem.joins(product_variant: :product)
                               .where(products: { pizza_party_role: party_role })
                               .select(:order_id)

    @orders = Order.completed
                   .in_bake_day_range(@start_date, @end_date)
                   .where(id: party_order_ids)
                   .includes(:customer, :bake_day,
                             order_items: { product_variant: [ :variant_cost_prices, :product ] })
                   .sort_by { |order| [ order.bake_day.baked_on, order.created_at ] }

    @summary = PizzaPartyRevenueService.call(@orders)
    # Détail par commande party (une party = une commande) pour le tableau.
    @rows = @orders.map { |order| [ order, PizzaPartyRevenueService.call([ order ]) ] }
  end

  # Reporting des versements Stripe (#49). Appels Stripe live (mis en cache court
  # par le service) ; en cas d'échec Stripe, `@report.error` porte un message FR
  # et la vue affiche une alerte propre — jamais de 500.
  def payouts
    @start_date = parsed_date(params[:start_date]) || Date.current.beginning_of_month
    @end_date = parsed_date(params[:end_date]) || Date.current
    @end_date = @start_date if @end_date < @start_date

    @report = StripePayoutReportService.new(start_date: @start_date, end_date: @end_date).call
  end

  private

  def parsed_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end
end
