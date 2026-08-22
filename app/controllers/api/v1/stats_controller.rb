# frozen_string_literal: true

module Api
  module V1
    class StatsController < BaseController
      def index
        start_date = parse_date(params[:start_date]) || 30.days.ago.to_date
        end_date = parse_date(params[:end_date]) || Date.current
        revenue = Order.revenue_between(start_date, end_date)

        render json: {
          data: {
            period: { start_date: start_date, end_date: end_date },
            revenue_cents: revenue,
            revenue_euros: (revenue / 100.0).round(2),
            sales_by_product: Order.sales_by_product_between(start_date, end_date),
            top_customers: Order.top_customers_between(start_date, end_date),
            sales_by_month: Order.sales_by_month_between(start_date, end_date)
          },
          _links: base_links
        }
      end

      private

      def parse_date(value)
        Date.iso8601(value) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
