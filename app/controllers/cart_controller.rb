class CartController < ApplicationController
  def show
    remove_unavailable_cart_items!
    sync_pizza_party_forfait!
    @cart = session[:cart] || []
    # Panier Pizza party privée : daté par la date/créneau choisis sur la page
    # événements, pas par une fournée (#pizza-parties).
    @party_cart = PizzaPartyForfaitService.party_cart?(@cart)
    @party_date = Date.iso8601(session[:party_date]) if @party_cart && session[:party_date].present?
    @party_slot = session[:party_slot] if @party_cart
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

    # Si un jour de cuisson est déjà choisi, refuser une variante non disponible ce jour-là.
    selected_bake_day_id = bake_day_id.presence || session[:bake_day_id]
    if selected_bake_day_id.present?
      selected_bake_day = BakeDay.find_by(id: selected_bake_day_id)
      if selected_bake_day && !variant.available_on_weekday?(selected_bake_day.baked_on.wday)
        respond_to_unavailable
        return
      end
    end

    # Pizza party privée (#pizza-parties) : la réservation exige une date + un
    # créneau (midi/soir) choisis dans le calendrier de disponibilités, et un
    # panier party ne se mélange pas aux articles ordinaires (une commande party
    # n'a pas de fournée : du pain dedans n'apparaîtrait sur aucune feuille de
    # production). Le créneau est revalidé côté serveur (page périmée/forgée).
    if variant.product.pizza_party_role_party?
      party_date, party_slot = parse_party_slot_choice(params[:party_slot_choice])

      unless party_date && PartyEvent.private_slot_available?(party_date, party_slot)
        redirect_back_or_events(alert: "Ce créneau n'est plus disponible. Choisis une autre date pour ta Pizza party.")
        return
      end

      if PizzaPartyForfaitService.regular_items?(session[:cart])
        redirect_back_or_events(alert: "Termine d'abord ta commande en cours : la Pizza party se réserve dans une commande séparée.")
        return
      end

      session[:party_date] = party_date.iso8601
      session[:party_slot] = party_slot
    elsif PizzaPartyForfaitService.party_cart?(session[:cart]) && !variant.product.pizza_party_role_forfait?
      respond_to do |format|
        format.html { redirect_to cart_path, alert: "Ton panier contient une Pizza party : termine cette réservation avant de commander autre chose." }
        format.json { render json: { error: "Ton panier contient une Pizza party : termine cette réservation avant de commander autre chose." }, status: :unprocessable_entity }
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

    sync_pizza_party_forfait!

    respond_to do |format|
      # Une réservation party continue naturellement vers le panier (sa date et
      # son créneau y sont récapitulés) ; le reste retourne au catalogue.
      format.html { redirect_to variant.product.pizza_party_role_party? ? cart_path : catalog_path, notice: "Produit ajouté au panier" }
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
      sync_pizza_party_forfait!
      redirect_to cart_path, notice: "Panier mis à jour"
    else
      redirect_to cart_path, alert: "Quantité invalide"
    end
  end

  def remove
    session[:cart] = (session[:cart] || []).reject { |item| item["product_variant_id"] == params[:id] }
    sync_pizza_party_forfait!
    clear_party_selection_unless_party_cart!
    redirect_to cart_path, notice: "Produit retiré du panier"
  end

  def update_bake_day
    bake_day = BakeDay.find_by(id: params[:bake_day_id])

    if bake_day && bake_day.can_order? && !BakeCapacityService.new(bake_day).fully_booked?
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
  def sync_pizza_party_forfait!
    session[:cart] = PizzaPartyForfaitService.sync(session[:cart])
  end

  # NOTE merge #87 : calculate_subtotal/calculate_discount supprimés ici.
  # La logique de remise du panier passe désormais par les helpers de
  # ApplicationController (current_cart_subtotal_cents / _discount_cents / _total_cents),
  # eux-mêmes adossés à GroupDiscountService (remises ciblées #87).

  # Plus de party dans le panier → la date/créneau choisis n'ont plus d'objet.
  def clear_party_selection_unless_party_cart!
    return if PizzaPartyForfaitService.party_cart?(session[:cart])

    session[:party_date] = nil
    session[:party_slot] = nil
  end

  # « YYYY-MM-DD|midi » → [Date, "midi"], ou [nil, nil] si invalide.
  def parse_party_slot_choice(raw)
    date_str, slot = raw.to_s.split("|", 2)
    return [ nil, nil ] unless PartyEvent.slots.key?(slot.to_s)

    [ Date.iso8601(date_str.to_s), slot ]
  rescue Date::Error
    [ nil, nil ]
  end

  def redirect_back_or_events(alert:)
    respond_to do |format|
      format.html { redirect_to evenements_path, alert: alert }
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
    # Récupérer tous les jours de cuisson futurs disponibles (cf. BakeDay::COOKING_WDAYS)
    available_bake_days = BakeDay.future
                                  .where("cut_off_at > ?", Time.current)
                                  .ordered
                                  .select { |bd| bd.can_order? && BakeDay::COOKING_WDAYS.include?(bd.baked_on.wday) }

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
