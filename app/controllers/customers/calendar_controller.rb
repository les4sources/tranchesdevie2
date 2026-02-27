module Customers
  class CalendarController < ApplicationController
    before_action :authenticate_customer!

    def show
      # Only show future bake days (today and later)
      @bake_days = BakeDay.where("baked_on >= ?", Date.current)
                          .order(baked_on: :asc)
      @planned_orders = current_customer.orders
                                        .where(source: :calendar)
                                        .where.not(status: :cancelled)
                                        .includes(:order_items, :bake_day)
                                        .index_by(&:bake_day_id)
      @wallet = current_customer.wallet || current_customer.create_wallet!
      @committed_cents = current_customer.orders.where(status: :planned, source: :calendar).sum(:total_cents)
      @available_balance_cents = @wallet.balance_cents - @committed_cents
      @product_variants = ProductVariant.where(active: true).includes(:product)
    end

    def update_day
      bake_day = BakeDay.find(params[:bake_day_id])
      items = params[:items] || []

      if items.empty?
        # Cancel the planned order if exists
        order = current_customer.orders.planned.find_by(bake_day: bake_day, source: :calendar)
        if order
          result = PlannedOrderService.cancel(order: order)
          if result[:error]
            render json: { error: result[:error] }, status: :unprocessable_entity
            return
          end
        end
        render json: { success: true }
      else
        # Create or update the planned order
        result = PlannedOrderService.upsert(
          customer: current_customer,
          bake_day: bake_day,
          items: items.map { |item| item.permit(:product_variant_id, :qty).to_h.symbolize_keys }
        )

        if result[:error]
          render json: { error: result[:error] }, status: :unprocessable_entity
        else
          render json: {
            success: true,
            order_id: result[:order].id,
            total_cents: result[:order].total_cents
          }
        end
      end
    end

    private

    def authenticate_customer!
      unless customer_signed_in?
        respond_to do |format|
          format.html { redirect_to customer_login_path }
          format.json { render json: { error: 'Non autorisé' }, status: :unauthorized }
        end
      end
    end
  end
end
