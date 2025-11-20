class Admin::BakeDaysController < Admin::BaseController
  before_action :set_bake_day, only: [:show, :edit, :update, :destroy]

  def index
    @bake_days = BakeDay.order(:baked_on).reverse_order
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
    respond_to do |format|
      if @bake_day.update(bake_day_params)
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
    params.require(:bake_day).permit(:baked_on, :cut_off_at, :internal_note)
  end
end

