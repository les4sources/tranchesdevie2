module Admin
  # Ateliers (#208) : « il pourrait y avoir un onglet en plus, ateliers, et
  # c'est vraiment la gestion de tous les ateliers, avec quel revenu par
  # atelier ».
  class WorkshopsController < Admin::BaseController
    before_action :set_workshop, only: [ :edit, :update, :destroy ]
    before_action :load_artisans, only: [ :new, :create, :edit, :update ]

    def index
      @workshops = Workshop.ordered.includes(:artisans)
      @upcoming = @workshops.select { |workshop| workshop.held_on >= Date.current }
      @past = @workshops.reject { |workshop| workshop.held_on >= Date.current }
      # Taux de répartition applicable aujourd'hui — nil tant qu'il n'est pas
      # tranché, et l'écran le dit plutôt que d'inventer un chiffre.
      @rate_basis_points = RevenueParameter.workshop_basis_points_on
    end

    def new
      @workshop = Workshop.new(held_on: Date.current)
    end

    def create
      @workshop = Workshop.new(workshop_params)

      if @workshop.save
        redirect_to admin_workshops_path, notice: "Atelier créé."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @workshop.update(workshop_params)
        redirect_to admin_workshops_path, notice: "Atelier modifié."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @workshop.destroy!

      redirect_to admin_workshops_path, notice: "Atelier supprimé."
    end

    private

    def set_workshop
      @workshop = Workshop.find(params[:id])
    end

    def load_artisans
      @artisans = Artisan.active.order(:name)
    end

    def workshop_params
      params.require(:workshop)
            .permit(:held_on, :title, :description, :notes, :revenue_euros, artisan_ids: [])
    end
  end
end
