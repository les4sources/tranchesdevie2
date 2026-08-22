# frozen_string_literal: true

module Admin
  module Settings
    # Édition des parts de revenu d'un artisan, historisées par date (#54).
    # Chaque artisan a une liste de paliers (% littéral à partir d'une date) ;
    # la part applicable à une date est le palier le plus récent (cf.
    # Artisan#revenue_share_percent). Aucune valeur par défaut : tout est saisi
    # ici (décision Michael 25/06).
    class ArtisanRevenueSharesController < Admin::BaseController
      before_action :set_artisan
      before_action :set_revenue_share, only: [ :edit, :update, :destroy ]

      def index
        @revenue_shares = @artisan.artisan_revenue_shares.ordered
      end

      def new
        @revenue_share = @artisan.artisan_revenue_shares.new(active_from: Date.current)
      end

      def create
        @revenue_share = @artisan.artisan_revenue_shares.new(revenue_share_params)

        if @revenue_share.save
          redirect_to admin_settings_artisan_revenue_shares_path(@artisan), notice: "Part de revenu enregistrée"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @revenue_share.update(revenue_share_params)
          redirect_to admin_settings_artisan_revenue_shares_path(@artisan), notice: "Part de revenu mise à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @revenue_share.destroy
        redirect_to admin_settings_artisan_revenue_shares_path(@artisan), notice: "Palier supprimé"
      end

      private

      def set_artisan
        @artisan = Artisan.find(params[:artisan_id])
      end

      def set_revenue_share
        @revenue_share = @artisan.artisan_revenue_shares.find(params[:id])
      end

      def revenue_share_params
        params.require(:artisan_revenue_share).permit(:percent, :active_from)
      end
    end
  end
end
