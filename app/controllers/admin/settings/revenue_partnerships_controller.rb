# frozen_string_literal: true

module Admin
  module Settings
    # Gestion des partenariats de revenu boulangers (#54). Un partenariat
    # regroupe des artisans qui mettent en commun leur revenu brut sur une
    # période, puis se le répartissent à parts égales (poids 1 par défaut).
    # Cas concret : Romane & Stéphanie, 50/50.
    #
    # La composition est éditée via une liste de cases à cocher (parts égales).
    # Le modèle porte un poids par membre pour permettre un partage pondéré à
    # l'avenir ; l'UI se limite ici à des parts égales.
    class RevenuePartnershipsController < Admin::BaseController
      before_action :set_partnership, only: [ :edit, :update, :destroy ]

      def index
        @partnerships = RevenuePartnership.ordered.includes(:artisans)
      end

      def new
        @partnership = RevenuePartnership.new(active: true)
      end

      def create
        @partnership = RevenuePartnership.new(partnership_params)

        if @partnership.save
          redirect_to admin_settings_revenue_partnerships_path, notice: "Partenariat créé"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @partnership.update(partnership_params)
          redirect_to admin_settings_revenue_partnerships_path, notice: "Partenariat mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @partnership.destroy
        redirect_to admin_settings_revenue_partnerships_path, notice: "Partenariat supprimé"
      end

      private

      def set_partnership
        @partnership = RevenuePartnership.find(params[:id])
      end

      # `artisan_ids` (parts égales) est transformé en memberships via
      # l'association `has_many :artisans, through:` : Rails crée/supprime les
      # `revenue_partnership_memberships` en conséquence. Le poids reste à sa
      # valeur par défaut (1) — répartition équitable.
      def partnership_params
        params.require(:revenue_partnership)
              .permit(:name, :active, artisan_ids: [])
      end
    end
  end
end
