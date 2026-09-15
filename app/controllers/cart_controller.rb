class CartController < ApplicationController
  def show
    remove_unavailable_cart_items!
    @cart = session[:cart] || []
    # Panier Pizza party privée : daté par la date/créneau choisis sur la page
    # événements, pas par une fournée (#pizza-parties).
    # Inscription à une party PUBLIQUE : datée par son événement.
    @public_party_cart = public_party_in_cart?
    @public_party_event = PartyEvent.public_events.not_deleted.find_by(id: session[:public_party_event_id]) if @public_party_cart
    @bake_day_id = session[:bake_day_id]
    @bake_day = BakeDay.find_by(id: @bake_day_id) if @bake_day_id
    @customer = current_customer_for_cart
    @subtotal = current_cart_subtotal_cents
    @discount_cents = current_cart_discount_cents
    @total = current_cart_total_cents
    @available_bake_days = load_next_available_bake_days
    @bake_day_capacities = @available_bake_days.each_with_object({}) do |bd, hash|
      svc = BakeCapacityService.new(bd)
      hash[bd.id] = { fill_percentage: svc.fill_percentage, fully_booked: svc.fully_booked? }
    end
    @phone_e164 = session[:phone_e164] if phone_verified?
    # Vérifier si le bake_day actuel est toujours disponible
    if @bake_day && !@bake_day.can_order?
      @bake_day = nil
      @bake_day_id = nil
      session[:bake_day_id] = nil
    end
    # Clear selection if selected bake_day is fully booked
    if @bake_day && @bake_day_capacities.dig(@bake_day.id, :fully_booked)
      @bake_day = nil
      @bake_day_id = nil
      session[:bake_day_id] = nil
    end
  end

  def add
    variant = ProductVariant.find(params[:product_variant_id])
    bake_day_id = params[:bake_day_id]

    unless variant.active? && variant.product.channel == "store" && variant.channel == "store"
      respond_to_unavailable
      return
    end

    unless variant.visible_to?(current_customer)
      respond_to_unavailable
      return
    end

    # Une party PRIVÉE ne se réserve plus par le panier (#pizza-parties) : elle
    # passe par une demande, que la boulangerie valide. Le refus s'appuie sur le
    # MODÈLE (`Product#cartable?`), pas sur une condition locale : cette action
    # accepte n'importe quel `product_variant_id`, et un pâton privé glissé dans
    # un panier de pain produirait une commande que l'index des parties et le
    # barème boulangers compteraient comme une party.
    unless variant.product.cartable?
      respond_to do |format|
        format.html { redirect_to pizza_party_privee_path, alert: "Une Pizza party privée se réserve depuis sa page dédiée, pas par le panier." }
        format.json { render json: { error: "Une Pizza party privée se réserve depuis sa page dédiée." }, status: :unprocessable_entity }
      end
      return
    end

    # Si un jour de cuisson est déjà choisi, refuser une variante non disponible ce jour-là.
    selected_bake_day_id = bake_day_id.presence || session[:bake_day_id]
    if selected_bake_day_id.present?
      selected_bake_day = BakeDay.find_by(id: selected_bake_day_id)
      if selected_bake_day && !variant.available_on_weekday?(selected_bake_day.baked_on.wday)
        respond_to_unavailable
        return
      end
    end

    if variant.product.pizza_party_role_public_party?
      # Inscription à une party PUBLIQUE : rattachée à SON événement (jauge et
      # clôture revérifiées ici, puis sous verrou au paiement), et jamais
      # mélangée à d'autres articles ni à un autre événement.
      event = PartyEvent.public_events.not_deleted.find_by(id: params[:public_party_event_id])

      unless event&.registration_open?
        redirect_back_or_public_parties(alert: "Les inscriptions pour cet événement ne sont pas ouvertes.")
        return
      end

      remaining = event.seats_remaining
      if remaining && requested_quantity > remaining
        redirect_back_or_public_parties(alert: remaining.zero? ? "Cet événement est complet." : "Il ne reste que #{remaining} place#{"s" if remaining > 1} pour cet événement.")
        return
      end

      if non_public_items_in_cart?
        redirect_back_or_public_parties(alert: "Ton panier contient déjà des articles de la boulangerie. Vide-le (bouton ci-dessous) ou termine cette commande : l'inscription à la Pizza party se règle à part.")
        return
      end

      if session[:public_party_event_id].present? && session[:public_party_event_id] != event.id &&
         public_party_in_cart?
        redirect_back_or_public_parties(alert: "Ton panier contient déjà une inscription pour une autre date : termine-la d'abord.")
        return
      end

      session[:public_party_event_id] = event.id
    elsif public_party_in_cart?
      respond_to do |format|
        format.html { redirect_to cart_path, alert: "Ton panier contient une inscription Pizza party : termine-la avant de commander autre chose." }
        format.json { render json: { error: "Ton panier contient une inscription Pizza party : termine-la avant de commander autre chose." }, status: :unprocessable_entity }
      end
      return
    end

    session[:bake_day_id] = bake_day_id if bake_day_id.present?
    session[:cart] ||= []

    existing_item = session[:cart].find { |item| item["product_variant_id"] == variant.id.to_s }

    if existing_item
      existing_item["qty"] = existing_item["qty"].to_i + requested_quantity
    else
      session[:cart] << {
        "product_variant_id" => variant.id.to_s,
        "qty" => requested_quantity,
        "name" => variant.name,
        "price_cents" => variant.price_cents
      }
    end

    respond_to do |format|
      # Une inscription publique reste sur la page des parties (pour ajouter
      # adultes ET enfants) ; le reste retourne au catalogue.
      format.html do
        if variant.product.pizza_party_role_public_party?
          redirect_to pizza_parties_path, notice: "Ajouté au panier ! Ajoute d'autres personnes ou passe au panier pour finaliser."
        else
          redirect_to catalog_path, notice: "Produit ajouté au panier"
        end
      end
      format.json do
        render json: {
          cart_count: current_cart_count,
          variant_qty: current_cart_variant_qty(variant.id),
          message: success_message(variant),
          mini_cart_html: render_to_string(
            partial: "cart/mini_cart",
            formats: [ :html ],
            locals: {
              items: current_cart_items,
              total_cents: current_cart_total_cents,
              subtotal_cents: current_cart_subtotal_cents,
              discount_cents: current_cart_discount_cents,
              customer: current_customer_for_cart,
              count: current_cart_count
            }
          )
        }, status: :created
      end
    end
  end

  def update
    cart = session[:cart] || []
    item = cart.find { |i| i["product_variant_id"] == params[:id] }

    if item && params[:qty].to_i > 0
      item["qty"] = params[:qty].to_i
      session[:cart] = cart
        redirect_to cart_path, notice: "Panier mis à jour"
    else
      redirect_to cart_path, alert: "Quantité invalide"
    end
  end

  def remove
    session[:cart] = (session[:cart] || []).reject { |item| item["product_variant_id"] == params[:id] }
    clear_public_party_selection_unless_needed!
    redirect_to cart_path, notice: "Produit retiré du panier"
  end

  # Vide le panier d'un coup (#pizza-parties). Sert au client coincé par le refus
  # des paniers mixtes : sans ce bouton, il devait retirer ses articles un par un
  # — en supposant qu'il ait compris que c'était son panier qui le bloquait.
  def clear
    session[:cart] = []
    clear_public_party_selection_unless_needed!

    redirect_back fallback_location: cart_path, notice: "Ton panier a été vidé."
  end

  def update_bake_day
    bake_day = BakeDay.find_by(id: params[:bake_day_id])

    # `open_to_customers?` plutôt que `can_order?` : le sélecteur ne propose que
    # des fournées ouvertes, mais un bake_day_id posté à la main ne doit pas
    # ouvrir une fournée réservée aux boulangers.
    if bake_day && bake_day.open_to_customers? && !BakeCapacityService.new(bake_day).fully_booked?
      session[:bake_day_id] = bake_day.id
      removed_count = remove_items_unavailable_for_bake_day!(bake_day)
      respond_to do |format|
        format.json { render json: { success: true, bake_day_id: bake_day.id, removed_count: removed_count } }
        format.html do
          notice = if removed_count.positive?
            "#{removed_count} article(s) ont été retirés car non disponibles ce jour de cuisson."
          end
          redirect_to cart_path, notice: notice
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, error: "Jour de cuisson non disponible" }, status: :unprocessable_entity }
        format.html { redirect_to cart_path, alert: "Jour de cuisson non disponible" }
      end
    end
  end

  def logout
    session[:customer_id] = nil
    session[:customer_authenticated_at] = nil
    session[:phone_e164] = nil
    session[:otp_verified] = false
    session[:otp_verified_at] = nil
    redirect_to cart_path, notice: "Déconnexion réussie"
  end

  private

  # Maintient la ligne « forfait Pizza party » (#68) cohérente avec le panier.
  # Idempotent : sans danger même appelé plusieurs fois par requête.
  # Le panier contient-il une inscription à une party PUBLIQUE ? (La party
  # privée, elle, ne passe plus par le panier — #pizza-parties.)
  def public_party_in_cart?
    Product.pizza_party_roles_in_cart(session[:cart]).include?("public_party")
  end

  def non_public_items_in_cart?
    (Product.pizza_party_roles_in_cart(session[:cart]) - [ "public_party" ]).any?
  end

  # NOTE merge #87 : calculate_subtotal/calculate_discount supprimés ici.
  # La logique de remise du panier passe désormais par les helpers de
  # ApplicationController (current_cart_subtotal_cents / _discount_cents / _total_cents),
  # eux-mêmes adossés à GroupDiscountService (remises ciblées #87).

  # Plus de party dans le panier → la sélection associée n'a plus d'objet.
  def clear_public_party_selection_unless_needed!
    session[:public_party_event_id] = nil unless public_party_in_cart?
  end

  # « YYYY-MM-DD|midi » → [Date, "midi"], ou [nil, nil] si invalide.
  def redirect_back_or_public_parties(alert:)
    respond_to do |format|
      format.html { redirect_to pizza_parties_path, alert: alert }
      format.json { render json: { error: alert }, status: :unprocessable_entity }
    end
  end

  def requested_quantity
    qty = params[:qty].to_i
    qty.positive? ? qty : 1
  end

  def success_message(variant)
    product_name = variant.product&.name
    variant_name = variant.name

    if product_name.present? && variant_name.present?
      "#{product_name} (#{variant_name}) ajouté à ton panier"
    elsif product_name.present?
      "#{product_name} ajouté à ton panier"
    else
      "#{variant_name.presence || 'Produit'} ajouté à ton panier"
    end
  end

  def load_next_available_bake_days
    # Même source que le bandeau du catalogue (cf. BakeDay.open_to_customers) :
    # les deux avaient divergé, et le catalogue annonçait des fournées que le
    # panier refusait.
    available_bake_days = BakeDay.open_to_customers

    # Grouper par jour de la semaine et prendre le premier de chaque groupe
    available_bake_days
      .group_by { |bd| bd.baked_on.wday }
      .values
      .map(&:first)
      .sort_by(&:baked_on)
  end

  def respond_to_unavailable
    respond_to do |format|
      format.html { redirect_to catalog_path, alert: "Ce produit n'est pas disponible" }
      format.json { render json: { error: "Ce produit n'est pas disponible" }, status: :unprocessable_entity }
    end
  end

  def remove_unavailable_cart_items!
    cart = session[:cart] || []
    return if cart.empty?

    bake_day = BakeDay.find_by(id: session[:bake_day_id]) if session[:bake_day_id].present?

    available = cart.select do |item|
      variant = ProductVariant.find_by(id: item["product_variant_id"])
      next false unless variant.present? && variant.active? && variant.channel == "store" && variant.product.present?
      next false if bake_day && !variant.available_on_weekday?(bake_day.baked_on.wday)

      true
    end
    removed_count = cart.size - available.size
    if removed_count.positive?
      session[:cart] = available
      flash.now[:notice] = "#{removed_count} article(s) ont été retirés de ton panier car ils ne sont plus disponibles."
    end
  end

  # Retire du panier les articles indisponibles pour ce jour de cuisson. Renvoie le nombre retiré.
  def remove_items_unavailable_for_bake_day!(bake_day)
    cart = session[:cart] || []
    return 0 if cart.empty?

    kept = cart.select do |item|
      variant = ProductVariant.find_by(id: item["product_variant_id"])
      variant.present? && variant.available_on_weekday?(bake_day.baked_on.wday)
    end
    removed_count = cart.size - kept.size
    session[:cart] = kept if removed_count.positive?
    removed_count
  end
end
