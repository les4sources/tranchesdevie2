# frozen_string_literal: true

# CRUD des points de retrait (#148). La suppression est un soft delete : le lieu
# disparaît des sélecteurs client mais reste lisible sur les commandes passées.
#
# Le cochage lieu ↔ fournée est bidirectionnel : il se fait ici (depuis la fiche
# du lieu, sur les fournées à venir) et depuis la fiche d'une fournée
# (Admin::BakeDaysController).
class Admin::PickupLocationsController < Admin::BaseController
  before_action :set_pickup_location, only: [ :edit, :update, :destroy ]

  def index
    @pickup_locations = PickupLocation.not_deleted.ordered
  end

  def new
    @pickup_location = PickupLocation.new
  end

  def create
    @pickup_location = PickupLocation.new(pickup_location_params)

    if @pickup_location.save
      redirect_to admin_pickup_locations_path, notice: "Point de retrait créé"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @pickup_location.update(pickup_location_params)
      redirect_to admin_pickup_locations_path, notice: "Point de retrait mis à jour"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @pickup_location.default?
      redirect_to admin_pickup_locations_path,
        alert: "Le point de retrait par défaut ne peut pas être supprimé."
      return
    end

    @pickup_location.soft_delete!
    redirect_to admin_pickup_locations_path, notice: "Point de retrait supprimé"
  end

  private

  def set_pickup_location
    @pickup_location = PickupLocation.not_deleted.find(params[:id])
  end

  def pickup_location_params
    params.require(:pickup_location).permit(:name, :description, :default, :position, bake_day_ids: [])
  end
end
