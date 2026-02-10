# frozen_string_literal: true

class Admin::ArtisansController < Admin::BaseController
  before_action :set_artisan, only: [:edit, :update]

  def index
    @artisans = Artisan.order(:name)
  end

  def new
    @artisan = Artisan.new(active: true)
  end

  def create
    @artisan = Artisan.new(artisan_params)

    if @artisan.save
      redirect_to admin_artisans_path, notice: "Artisan créé avec succès"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @artisan.update(artisan_params)
      redirect_to admin_artisans_path, notice: "Artisan mis à jour avec succès"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_artisan
    @artisan = Artisan.find(params[:id])
  end

  def artisan_params
    params.require(:artisan).permit(:name, :active)
  end
end
