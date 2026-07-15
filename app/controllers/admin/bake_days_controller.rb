class Admin::BakeDaysController < Admin::BaseController
  before_action :set_bake_day, only: [ :show, :edit, :update, :destroy, :confirm_cancel, :cancel, :pickup_sheet ]

  def index
    # Jours futurs (aujourd'hui et futurs)
    @future_bake_days = BakeDay.future.includes(:baking_artisans, orders: { order_items: { product_variant: [ :mold_type, { product: { product_flours: :flour } } ] } }).order(:baked_on)

    # Jours passés avec pagination par année et filtre par mois
    past_bake_days = BakeDay.past

    # Récupérer l'année sélectionnée (par défaut: année la plus récente)
    @selected_year = params[:year]&.to_i
    if @selected_year.nil?
      most_recent_year = BakeDay.past.order(baked_on: :desc).limit(1).pluck(Arel.sql("EXTRACT(YEAR FROM baked_on)::integer")).first
      @selected_year = most_recent_year if most_recent_year
    end

    # Filtrer par année
    if @selected_year
      past_bake_days = past_bake_days.where("EXTRACT(YEAR FROM baked_on) = ?", @selected_year)
    end

    # Récupérer le mois sélectionné (optionnel)
    @selected_month = params[:month]&.to_i

    # Filtrer par mois si sélectionné
    if @selected_month && @selected_month.between?(1, 12)
      past_bake_days = past_bake_days.where("EXTRACT(MONTH FROM baked_on) = ?", @selected_month)
    end

    @past_bake_days = past_bake_days.includes(:baking_artisans, orders: { order_items: { product_variant: [ :mold_type, { product: { product_flours: :flour } } ] } }).order(:baked_on)

    # Liste des années disponibles pour le filtre
    @available_years = BakeDay.past
                               .pluck(Arel.sql("DISTINCT EXTRACT(YEAR FROM baked_on)::integer"))
                               .sort
                               .reverse
  end

  def show
    @dashboard = Admin::BakeDayDashboard.new(@bake_day)
  end

  def new
    @bake_day = BakeDay.new
    # Le lieu par défaut est pré-coché (il sera de toute façon ouvert à la
    # création — cf. BakeDay#open_default_pickup_location).
    @bake_day.pickup_location_ids = [ PickupLocation.default_location&.id ].compact
  end

  def create
    @bake_day = BakeDay.new(bake_day_params)

    # Auto-calculate cut_off_at if not provided
    if @bake_day.baked_on.present? && @bake_day.cut_off_at.blank?
      @bake_day.cut_off_at = BakeDay.calculate_cut_off_for(@bake_day.baked_on)
    end

    if @bake_day.save
      redirect_to admin_bake_day_path(@bake_day), notice: "Jour de cuisson créé"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    attrs = bake_day_params
    attrs[:baking_artisan_ids] = attrs[:baking_artisan_ids].reject(&:blank?) if attrs[:baking_artisan_ids]
    @bake_day.assign_attributes(attrs)

    # Auto-calculate cut_off_at if baked_on changed and cut_off_at is blank
    if @bake_day.baked_on.present? && @bake_day.cut_off_at.blank?
      @bake_day.cut_off_at = BakeDay.calculate_cut_off_for(@bake_day.baked_on)
    end

    respond_to do |format|
      if @bake_day.save
        format.html { redirect_to admin_bake_day_path(@bake_day), notice: "Jour de cuisson mis à jour" }
        format.json { render json: { success: true, bake_day: { internal_note: @bake_day.internal_note } }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @bake_day.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @bake_day.destroy
    redirect_to admin_bake_days_path, notice: "Jour de cuisson supprimé"
  end

  # Feuille d'émargement PDF d'un point de retrait pour cette fournée (#148).
  # Un lieu supprimé reste imprimable tant qu'il porte des commandes.
  def pickup_sheet
    pickup_location = PickupLocation.find(params[:pickup_location_id])
    service = PickupSheetPdfService.new(@bake_day, pickup_location)

    send_data service.render,
      filename: service.filename,
      type: "application/pdf",
      disposition: "attachment"
  end

  # Écran de confirmation renforcée avant annulation : affiche l'impact chiffré
  # (commandes, montant à rembourser, ventilation par mode, SMS) et exige une
  # garde délibérée avant de pouvoir déclencher l'annulation réelle (#133).
  def confirm_cancel
    @preview = BakeDayCancellationService.new(@bake_day).preview
  end

  # Annule la fournée : rembourse tous les clients ayant payé (carte ou
  # portefeuille) et bascule leurs commandes en « annulée ».
  def cancel
    service = BakeDayCancellationService.new(@bake_day)

    # Garde idempotente : plus aucune commande annulable → on ne rembourse rien
    # et on n'envoie aucun SMS (pas d'erreur, message neutre).
    unless service.preview.any_orders?
      redirect_to admin_bake_day_path(@bake_day),
                  notice: "Aucune commande à annuler pour cette fournée."
      return
    end

    # Garde serveur : l'admin doit avoir retapé la date de la fournée. Sans elle,
    # aucune action (aucun remboursement, aucun SMS) — on renvoie vers l'écran.
    unless cancellation_confirmed?
      redirect_to confirm_cancel_admin_bake_day_path(@bake_day),
                  alert: "Confirmation invalide : la fournée n'a pas été annulée. " \
                         "Retapez la date exacte pour confirmer."
      return
    end

    result = service.call

    if result.success?
      redirect_to admin_bake_day_path(@bake_day), notice: cancellation_summary(result)
    else
      redirect_to admin_bake_day_path(@bake_day),
                  alert: "#{cancellation_summary(result)} — #{result.failures.size} échec(s) à reprendre : " \
                         "#{result.failures.map { |f| "#{f[:order]} (#{f[:error]})" }.join(', ')}"
    end
  end

  private

  # Garde délibérée : l'admin doit retaper la date de la fournée au format
  # JJ/MM/AAAA. Rattache la confirmation à CETTE fournée précise (un clic
  # distrait ou une confirmation générique ne suffit plus).
  def cancellation_confirmed?
    params[:confirmation].to_s.strip == @bake_day.baked_on.strftime("%d/%m/%Y")
  end

  def cancellation_summary(result)
    parts = [ "Fournée annulée : #{result.refunded_count} remboursement(s) " \
              "(#{format('%.2f', result.refunded_cents / 100.0)} €)" ]
    if result.manual_refund_orders.any?
      parts << "#{result.manual_refund_orders.size} à rembourser à la main " \
               "(#{result.manual_refund_orders.join(', ')})"
    end
    parts << "#{result.cancelled_without_refund_count} sans paiement" if result.cancelled_without_refund_count.positive?
    parts.join(" · ")
  end

  def set_bake_day
    @bake_day = BakeDay.find(params[:id])
  end

  def bake_day_params
    params.require(:bake_day).permit(:baked_on, :cut_off_at, :internal_note, :market_day,
      baking_artisan_ids: [], pickup_location_ids: [])
  end
end
