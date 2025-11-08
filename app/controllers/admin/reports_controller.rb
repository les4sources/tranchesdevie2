class Admin::ReportsController < Admin::BaseController
  def index
    @start_date = parsed_date(params[:start_date]) || Date.current.beginning_of_year
    @end_date = parsed_date(params[:end_date]) || Date.current
    @end_date = @start_date if @end_date < @start_date

    @sales_by_product = Order.sales_by_product_between(@start_date, @end_date)
    @revenue_cents = Order.revenue_between(@start_date, @end_date)
    @top_customers = Order.top_customers_between(@start_date, @end_date, limit: 10)
    @weekday_comparison = Order.sales_by_weekday_between(@start_date, @end_date, [2, 5])
    @monthly_sales = Order.sales_by_month_between(@start_date, @end_date)
    @orders_count = Order.completed.in_bake_day_range(@start_date, @end_date).distinct.count(:id)
    @average_order_value_cents = @orders_count.positive? ? (@revenue_cents.to_f / @orders_count).round : 0
  end

  private

  def parsed_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError
    nil
  end
end

