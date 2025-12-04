class Admin::OrdersController < Admin::BaseController
  before_action :set_order, only: [:show, :edit, :update, :update_status, :refund]
  before_action :load_form_dependencies, only: [:new, :create, :edit, :update]

  def index
    @orders = Order.includes(:customer, :bake_day).recent

    @orders = @orders.by_bake_day(BakeDay.find(params[:bake_day_id])) if params[:bake_day_id].present?
    @orders = @orders.where(status: params[:status]) if params[:status].present?

    @bake_days = BakeDay.future.ordered
  end

  def new
    @order = Order.new(status: :unpaid, customer_id: params[:customer_id])
    @selected_quantities = {}
    subtotal_cents = calculate_total_from_quantities(@selected_quantities)
    
    # Calculer la remise si un client est sélectionné
    if @order.customer_id.present?
      customer = Customer.includes(:group).find_by(id: @order.customer_id)
      discount_cents = calculate_discount(subtotal_cents, customer)
      @calculated_total_cents = subtotal_cents - discount_cents
    else
      @calculated_total_cents = subtotal_cents
    end
  end

  def show
  end

  def edit
    @selected_quantities = {}
    @order.order_items.each do |item|
      @selected_quantities[item.product_variant_id] = item.qty
    end
    
    subtotal_cents = calculate_total_from_quantities(@selected_quantities)
    
    # Calculer la remise si un client est sélectionné
    if @order.customer_id.present?
      customer = Customer.includes(:group).find_by(id: @order.customer_id)
      discount_cents = calculate_discount(subtotal_cents, customer)
      @calculated_total_cents = subtotal_cents - discount_cents
    else
      @calculated_total_cents = subtotal_cents
    end
  end

  def update
    permitted_params = order_form_params
    raw_quantities = permitted_params.delete(:variant_quantities) || {}
    @selected_quantities = normalize_variant_quantities(raw_quantities)
    @final_total_input = permitted_params.delete(:final_total_euros)

    subtotal_cents = calculate_total_from_quantities(@selected_quantities)
    
    # Calculer la remise si un client est sélectionné
    if permitted_params[:customer_id].present?
      customer = Customer.includes(:group).find_by(id: permitted_params[:customer_id])
      discount_cents = calculate_discount(subtotal_cents, customer)
      @calculated_total_cents = subtotal_cents - discount_cents
    else
      @calculated_total_cents = subtotal_cents
    end

    assign_total_cents!(@final_total_input)
    ensure_order_has_items!

    if @order.errors.any?
      render :edit, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      @order.update!(permitted_params)
      @order.order_items.destroy_all
      create_order_items!
    end

    redirect_to admin_order_path(@order), notice: 'Commande modifiée'
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def create
    permitted_params = order_form_params
    raw_quantities = permitted_params.delete(:variant_quantities) || {}
    @selected_quantities = normalize_variant_quantities(raw_quantities)
    @final_total_input = permitted_params.delete(:final_total_euros)

    @order = Order.new(permitted_params)
    subtotal_cents = calculate_total_from_quantities(@selected_quantities)
    
    # Calculer la remise si un client est sélectionné
    if @order.customer_id.present?
      customer = Customer.includes(:group).find_by(id: @order.customer_id)
      discount_cents = calculate_discount(subtotal_cents, customer)
      @calculated_total_cents = subtotal_cents - discount_cents
    else
      @calculated_total_cents = subtotal_cents
    end

    assign_total_cents!(@final_total_input)
    ensure_order_has_items!

    if @order.errors.any?
      render :new, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      @order.save!
      create_order_items!
    end

    redirect_to admin_order_path(@order), notice: 'Commande créée'
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def update_status
    new_status = params[:status]

    unless @order.can_transition_to?(new_status)
      redirect_to admin_order_path(@order), alert: 'Transition de statut invalide'
      return
    end

    @order.transition_to!(new_status)

    # Send ready SMS if status changed to ready (from paid or unpaid)
    if @order.ready? && @order.saved_change_to_status? && ['paid', 'unpaid'].include?(@order.status_before_last_save)
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

  def load_form_dependencies
    @customers = Customer.includes(:group).order(:last_name, :first_name)
    # Pour l'édition, permettre tous les jours de cuisson, pas seulement les futurs
    @bake_days = if action_name == 'edit' || action_name == 'update'
                   BakeDay.ordered
                 else
                   BakeDay.future.ordered
                 end
    @products = Product.not_deleted.active.includes(:product_variants).ordered
    @max_variant_count = @products.map { |product| product.product_variants.active.size }.max || 0
    @variant_lookup = @products.each_with_object({}) do |product, hash|
      product.product_variants.active.each do |variant|
        hash[variant.id] = variant
      end
    end
  end

  def order_form_params
    params.require(:order).permit(
      :customer_id,
      :bake_day_id,
      :status,
      :requires_invoice,
      :final_total_euros,
      variant_quantities: {}
    )
  end

  def normalize_variant_quantities(quantities)
    quantities.to_h.each_with_object({}) do |(variant_id, qty), hash|
      hash[variant_id.to_i] = qty.to_i
    end
  end

  def calculate_total_from_quantities(quantities)
    quantities.sum do |variant_id, qty|
      next 0 unless qty.positive?

      variant = @variant_lookup[variant_id]
      next 0 unless variant

      qty * variant.price_cents
    end
  end

  def calculate_discount(subtotal, customer)
    return 0 unless customer&.group&.discount_percent

    (subtotal * customer.group.discount_percent / 100.0).round
  end

  def assign_total_cents!(amount_input)
    total_cents = parse_euro_amount(amount_input)
    if total_cents.nil?
      @order.errors.add(:total_cents, 'doit être renseigné')
    else
      @order.total_cents = total_cents
    end
  end

  def parse_euro_amount(amount)
    return nil if amount.blank?

    normalized = amount.to_s.tr(',', '.')
    (BigDecimal(normalized) * 100).round
  rescue ArgumentError
    nil
  end

  def ensure_order_has_items!
    if @selected_quantities.none? { |_id, qty| qty.positive? }
      @order.errors.add(:base, 'La commande doit contenir au moins un article')
    end
  end

  def create_order_items!
    @selected_quantities.each do |variant_id, qty|
      next unless qty.positive?

      variant = @variant_lookup[variant_id]
      next unless variant

      @order.order_items.create!(
        product_variant: variant,
        qty: qty,
        unit_price_cents: variant.price_cents
      )
    end
  end
end

