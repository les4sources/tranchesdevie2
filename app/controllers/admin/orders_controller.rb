class Admin::OrdersController < Admin::BaseController
  before_action :set_order, only: [:show, :update_status, :refund]

  def index
    @orders = Order.includes(:customer, :bake_day).recent

    @orders = @orders.by_bake_day(BakeDay.find(params[:bake_day_id])) if params[:bake_day_id].present?
    @orders = @orders.where(status: params[:status]) if params[:status].present?

    @bake_days = BakeDay.future.ordered
  end

  def show
  end

  def update_status
    new_status = params[:status]

    unless @order.can_transition_to?(new_status)
      redirect_to admin_order_path(@order), alert: 'Transition de statut invalide'
      return
    end

    @order.transition_to!(new_status)

    # Send ready SMS if status changed to ready
    if @order.ready? && @order.saved_change_to_status? && @order.status_before_last_save == 'paid'
      SmsService.send_ready(@order)
    end

    redirect_to admin_order_path(@order), notice: 'Statut mis à jour'
  end

  def refund
    service = RefundService.new(@order)

    if service.call
      redirect_to admin_order_path(@order), notice: 'Remboursement effectué'
    else
      redirect_to admin_order_path(@order), alert: "Erreur: #{service.errors.join(', ')}"
    end
  end

  private

  def set_order
    @order = Order.find(params[:id])
  end
end

