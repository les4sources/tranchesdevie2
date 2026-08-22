# frozen_string_literal: true

module Admin
  module Settings
    # Édition des paramètres généraux historisés du calcul des revenus
    # boulangers (#54) : transport (cents/jour) et taux 4 Sources (points de
    # base). Un seul écran liste les deux clés et leurs paliers ; chaque palier
    # est saisi en unités lisibles (€ pour le transport, % pour le taux) et
    # converti vers l'entier stocké.
    class RevenueParametersController < Admin::BaseController
      before_action :set_revenue_parameter, only: [ :edit, :update, :destroy ]

      def index
        @parameters_by_key = RevenueParameter::KEYS.index_with do |key|
          RevenueParameter.for_key(key).ordered.to_a
        end
      end

      def new
        @revenue_parameter = RevenueParameter.new(key: requested_key, active_from: Date.current)
      end

      def create
        @revenue_parameter = RevenueParameter.new(revenue_parameter_params)

        if @revenue_parameter.save
          redirect_to admin_settings_revenue_parameters_path, notice: "Paramètre enregistré"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @revenue_parameter.update(revenue_parameter_params)
          redirect_to admin_settings_revenue_parameters_path, notice: "Paramètre mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @revenue_parameter.destroy
        redirect_to admin_settings_revenue_parameters_path, notice: "Palier supprimé"
      end

      private

      def set_revenue_parameter
        @revenue_parameter = RevenueParameter.find(params[:id])
      end

      def requested_key
        RevenueParameter::KEYS.include?(params[:key]) ? params[:key] : RevenueParameter::TRANSPORT
      end

      # Le formulaire saisit la valeur en unités lisibles (`value_input`) ; on la
      # convertit vers l'entier stocké selon la clé : € → cents (transport),
      # % → points de base (taux 4 Sources).
      def revenue_parameter_params
        permitted = params.require(:revenue_parameter).permit(:key, :active_from, :value_input)
        key = @revenue_parameter&.key || permitted[:key]

        {
          key: key,
          active_from: permitted[:active_from],
          value: convert_input(key, permitted[:value_input])
        }.compact
      end

      def convert_input(key, raw)
        return nil if raw.to_s.strip.blank?

        number = raw.to_s.tr(",", ".").to_f
        case key
        when RevenueParameter::TRANSPORT then (number * 100).round       # € → cents
        when RevenueParameter::FOUR_SOURCES_RATE then (number * 100).round # % → points de base
        else number.round
        end
      end
    end
  end
end
