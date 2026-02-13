class Admin::BakeDaysController < Admin::BaseController
  before_action :set_bake_day, only: [:show, :edit, :update, :destroy]

  def index
    # Jours futurs (aujourd'hui et futurs)
    @future_bake_days = BakeDay.future.includes(:baking_artisans).order(:baked_on)

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
    
    @past_bake_days = past_bake_days.includes(:baking_artisans).order(:baked_on)
    
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
  end

  def create
    @bake_day = BakeDay.new(bake_day_params)

    # Auto-calculate cut_off_at if not provided
    if @bake_day.baked_on.present? && @bake_day.cut_off_at.blank?
      @bake_day.cut_off_at = BakeDay.calculate_cut_off_for(@bake_day.baked_on)
    end

    if @bake_day.save
      redirect_to admin_bake_day_path(@bake_day), notice: 'Jour de cuisson créé'
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
        format.html { redirect_to admin_bake_day_path(@bake_day), notice: 'Jour de cuisson mis à jour' }
        format.json { render json: { success: true, bake_day: { internal_note: @bake_day.internal_note } }, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { success: false, errors: @bake_day.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @bake_day.destroy
    redirect_to admin_bake_days_path, notice: 'Jour de cuisson supprimé'
  end

  private

  def set_bake_day
    @bake_day = BakeDay.find(params[:id])
  end

  def bake_day_params
    params.require(:bake_day).permit(:baked_on, :cut_off_at, :internal_note, baking_artisan_ids: [])
  end
end

