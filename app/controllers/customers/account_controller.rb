class Customers::AccountController < ApplicationController
  before_action :authenticate_customer!

  def show
    load_account_orders
    @member_since = @customer.created_at
  end

  def edit
    @customer = current_customer
  end

  def update
    @customer = current_customer

    if @customer.update(customer_params)
      redirect_to customers_account_path, notice: "Profil mis à jour avec succès"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def cancel_order
    @order = current_customer.orders.find_by(id: params[:id])

    unless @order
      redirect_to customers_account_path, alert: "Commande introuvable"
      return
    end

    unless @order.can_be_cancelled_by_customer?
      redirect_to customers_account_path, alert: "Cette commande ne peut pas être annulée"
      return
    end

    @order.destroy
    redirect_to customers_account_path, notice: "Commande annulée avec succès"
  end

  # Pointage « J'ai récupéré ma commande » depuis « Mon compte ».
  #
  # En Turbo Stream, la page ne bouge pas : un client qui récupère trois fournées
  # en retard les pointe l'une après l'autre sans perdre son onglet ni sa position
  # de défilement (#291). Le format HTML garde la redirection historique — sans
  # JavaScript, le rechargement reste la seule façon de voir le résultat.
  def pickup_order
    @order = current_customer.orders.find_by(id: params[:id])

    return respond_to_pickup(alert: "Commande introuvable") unless @order

    unless @order.can_be_picked_up_by_customer?
      return respond_to_pickup(alert: "Cette commande ne peut pas être marquée comme récupérée")
    end

    @order.transition_to!(:picked_up)
    respond_to_pickup(notice: "Commande marquée comme récupérée. Bon appétit !")
  end

  private

  # La page a pu se périmer entre son affichage et le clic (commande déjà pointée
  # par la boulangerie) : le flux d'erreur renvoie donc AUSSI la ligne dans son
  # état réel, pas seulement un message.
  def respond_to_pickup(notice: nil, alert: nil)
    respond_to do |format|
      format.turbo_stream do
        @notice = notice
        @alert = alert
        load_account_orders
        render :pickup_order
      end
      format.html { redirect_to customers_account_path, notice: notice, alert: alert }
    end
  end

  # Les commandes et tous les compteurs qui en dépendent, recalculés d'un bloc :
  # l'affichage initial et le flux Turbo lisent exactement les mêmes chiffres.
  def load_account_orders
    @customer = current_customer
    @orders = @customer.orders
                      .visible_to_customer
                      .includes(:bake_day, :order_issues, order_items: { product_variant: :product })
                      .order("bake_days.baked_on DESC")
                      .to_a
    @orders_count = @orders.size
    @ready_count = @orders.count { |o| o.status == "ready" }
    @total_spent_cents = @orders.reject { |o| o.status == "cancelled" }.sum(&:total_cents)
    @status_counts = Order.statuses.keys.index_with { |status| @orders.count { |o| o.status == status } }
                          .merge("all" => @orders.size)
  end

  def customer_params
    params.require(:customer).permit(:first_name, :last_name, :phone_e164, :email, :sms_opt_out, :email_opt_out)
  end
end
