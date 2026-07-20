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

    @orders = party_orders_with_role(:party)
    @summary = PizzaPartyRevenueService.call(@orders)
    @rows = @orders.map { |order| [ order, PizzaPartyRevenueService.call([ order ]) ] }

    @public_orders = party_orders_with_role(:public_party)
    @public_summary = PublicPartyRevenueService.call(@public_orders)
    @public_rows = @public_orders.map { |order| [ order, PublicPartyRevenueService.call([ order ]) ] }

    # Parties publiques HISTORIQUES (BilletWeb) : ventes agrégées sur l'événement,
    # barème boulangers appliqué rétroactivement (part due par la fondation 4S).
    @historical_events = PartyEvent.public_events.historical
                                   .where(held_on: @start_date..@end_date)
                                   .order(:held_on)
    @historical_rows = @historical_events.map { |event| [ event, HistoricalPartyRevenueService.call(event) ] }
    @historical_totals = @historical_rows.each_with_object(Hash.new(0)) do |(_event, r), acc|
      acc[:persons] += r.persons
      acc[:adults] += r.adults
      acc[:children] += r.children
      acc[:sourciers] += r.sourciers
      acc[:sale_cents] += r.sale_cents
      acc[:bakers_cents] += r.bakers_cents
      acc[:four_sources_cents] += r.four_sources_cents
      acc[:fees_cents] += r.fees_cents
      acc[:net_to_four_sources_cents] += r.net_to_four_sources_cents
      acc[:four_sources_effective_cents] += r.four_sources_effective_cents
    end
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

  # Commandes finalisées de la période contenant un article d'un produit au rôle
  # pizza party donné (:party ou :public_party), préchargées pour le calcul.
  def party_orders_with_role(role)
    order_ids = OrderItem.joins(product_variant: :product)
                         .where(products: { pizza_party_role: Product.pizza_party_roles[role] })
                         .select(:order_id)

    Order.completed
         .in_bake_day_range(@start_date, @end_date)
         .where(id: order_ids)
         .includes(:customer, :bake_day,
                   order_items: { product_variant: [ :variant_cost_prices, :product ] })
         .sort_by { |order| [ order.bake_day.baked_on, order.created_at ] }
  end

  def parsed_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end
end
