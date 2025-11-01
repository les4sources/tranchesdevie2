class OrdersController < ApplicationController
  def show
    @order = Order.find_by!(public_token: params[:token])
  end
end

