class ApplicationController < ActionController::Base
  # Browser restriction removed to support a wider range of client browsers
  # The application uses import maps, Tailwind CSS, and Stimulus which are compatible with most modern browsers
  # allow_browser versions: :modern  # Commented out to allow older browsers

  include CustomerAuthentication

  # Jeton CSRF refusé : le formulaire a été affiché avec une session que le
  # navigateur n'envoie plus (onglet ouvert depuis longtemps, page restaurée du
  # cache du téléphone, navigateur intégré de Facebook/Instagram qui bloque les
  # cookies…). Rails rendait alors la page anglaise « 422 Unprocessable
  # Content », sans issue pour le client, et Sentry ne la voyait pas (exception
  # ignorée par défaut). On la signale et on renvoie le client sur sa page,
  # rechargée avec un jeton neuf, avec une consigne claire.
  rescue_from ActionController::InvalidAuthenticityToken, with: :handle_invalid_authenticity_token

  helper_method :current_cart_items, :current_cart_total_cents, :current_cart_count, :current_cart_variant_qty, :phone_verified?, :current_cart_subtotal_cents, :current_cart_discount_cents, :current_customer_for_cart, :admin_authenticated?

  private

  INVALID_TOKEN_HINT = "Si tu as ouvert le lien depuis Facebook ou Instagram, ouvre plutôt la page dans ton navigateur habituel (Safari, Chrome…) : leur navigateur intégré pose un problème connu avec notre site.".freeze
  INVALID_TOKEN_MESSAGE = "Ta page n'était plus à jour : nous l'avons rechargée. Réessaie. #{INVALID_TOKEN_HINT}".freeze

  def handle_invalid_authenticity_token
    report_invalid_authenticity_token

    respond_to do |format|
      format.html { redirect_back_or_to root_path, alert: INVALID_TOKEN_MESSAGE }
      format.json { render json: { error: "Ta page n'était plus à jour. Recharge-la et réessaie. #{INVALID_TOKEN_HINT}" }, status: :unprocessable_content }
      format.any { head :unprocessable_content }
    end
  end

  def report_invalid_authenticity_token
    return unless defined?(Sentry) && Sentry.initialized?

    Sentry.capture_message(
      "Jeton CSRF invalide (#{controller_name}##{action_name})",
      level: :warning,
      extra: {
        path: request.path,
        referer: request.referer,
        user_agent: request.user_agent,
        session_cookie_present: cookies[Rails.application.config.session_options[:key]].present?
      }
    )
  end

  # wday du jour de cuisson sélectionné en session (s'il est encore commandable), sinon nil.
  # Sert à filtrer le catalogue selon la restriction de jour des variantes.
  def selected_bake_day_wday
    return nil if session[:bake_day_id].blank?

    bake_day = BakeDay.find_by(id: session[:bake_day_id])
    return nil unless bake_day&.can_order?

    bake_day.baked_on.wday
  end

  def admin_authenticated?
    session[:admin_authenticated] == true &&
      session[:admin_authenticated_at].present? &&
      Time.current - Time.parse(session[:admin_authenticated_at]) < 24.hours
  end

  def current_cart_items
    @current_cart_items = build_cart_items(session[:cart] || [])
  end

  def current_cart_subtotal_cents
    current_cart_items.sum { |item| item[:total_cents] }
  end

  def current_cart_discount_cents
    customer = current_customer_for_cart
    return 0 unless customer

    GroupDiscountService.new(customer).total_discount_cents(
      current_cart_items.map { |item| { variant: item[:variant], qty: item[:qty] } }
    )
  end

  def current_cart_total_cents
    current_cart_subtotal_cents - current_cart_discount_cents
  end

  def current_customer_for_cart
    return current_customer if customer_signed_in?
    return nil unless session[:phone_e164]

    Customer.find_by(phone_e164: session[:phone_e164])
  end

  def current_cart_count
    (session[:cart] || []).sum { |item| item["qty"].to_i }
  end

  def current_cart_variant_qty(variant_id)
    cart = session[:cart] || []
    item = cart.find { |i| i["product_variant_id"] == variant_id.to_s }
    item ? item["qty"].to_i : 0
  end

  def build_cart_items(cart)
    return [] if cart.blank?

    variant_ids = cart.map { |item| item["product_variant_id"] }.compact.uniq
    variants = ProductVariant.includes(:product).where(id: variant_ids).index_by { |variant| variant.id.to_s }

    cart.filter_map do |item|
      variant = variants[item["product_variant_id"]]
      next unless variant

      qty = item["qty"].to_i

      {
        variant_id: variant.id,
        variant: variant,
        product_name: variant.product.name,
        variant_name: variant.name,
        qty: qty,
        price_cents: variant.price_cents,
        total_cents: variant.price_cents * qty
      }
    end
  end

  def phone_verified?
    # Si le client est connecté, considérer le téléphone comme vérifié
    if customer_signed_in?
      # Synchroniser la session avec les données du client connecté
      session[:phone_e164] = current_customer.phone_e164
      session[:otp_verified] = true
      session[:otp_verified_at] = Time.current.to_i
      return true
    end

    # Sinon, vérifier la session OTP classique
    return false unless session[:otp_verified] == true
    return false unless session[:otp_verified_at].present?
    return false unless session[:phone_e164].present?

    verified_at = Time.at(session[:otp_verified_at])
    verified_at > 1.year.ago
  end
end
