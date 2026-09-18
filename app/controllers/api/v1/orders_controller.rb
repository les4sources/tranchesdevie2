# frozen_string_literal: true

module Api
  module V1
    class OrdersController < BaseController
      # Précharge tout ce que le sérialiseur lit : sans ça, l'index d'un mois de
      # Pizza parties fait une requête par commande pour la party, la demande, le
      # client et le remboursement (#290).
      INDEX_INCLUDES = [
        :payment, :wallet_transactions, :customer, :party_request, :party_event,
        { order_items: { product_variant: :product } }
      ].freeze

      def index
        scope = Order.recent.includes(INDEX_INCLUDES)
        scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id]
        scope = scope.where(bake_day_id: params[:bake_day_id]) if params[:bake_day_id]
        scope = scope.where(status: params[:status]) if params[:status].present? && Order.statuses.key?(params[:status])
        scope = scope.where(source: params[:source]) if params[:source].present? && Order.sources.key?(params[:source])

        scope = apply_kind_filter(scope)
        return if performed?

        scope = apply_held_on_filter(scope)
        return if performed?

        scope = apply_paid_filter(scope)
        return if performed?

        render_collection(scope, OrderSerializer)
      end

      def show
        order = Order.includes(INDEX_INCLUDES).find(params[:id])
        render_resource(order, OrderSerializer)
      end

      private

      # `kind=private_party` : les commandes rattachées à une party PRIVÉE — ce
      # que Claudy rattache à un séjour (#290). Seule valeur acceptée pour
      # l'instant : un `kind` inconnu est une erreur, pas un filtre ignoré, sinon
      # l'appelant croit filtrer alors qu'il reçoit tout.
      def apply_kind_filter(scope)
        kind = params[:kind].to_s
        return scope if kind.blank?

        unless kind == "private_party"
          render_error(400, "invalid_filter",
                       "Filtre « kind » inconnu : « #{kind} ». Seule valeur acceptée : private_party.")
          return scope
        end

        scope.joins(:party_event).where(party_events: { kind: PartyEvent.kinds[:private_party] })
      end

      # Bornes INCLUSIVES sur la date de la party. La jointure est posée ici même
      # (et non conditionnée à `kind`) : filtrer sur une date de party exclut de
      # fait les commandes qui n'en ont pas, ce qui est le sens attendu.
      def apply_held_on_filter(scope)
        from = parse_filter_date(:held_on_from)
        return scope if performed?

        to = parse_filter_date(:held_on_to)
        return scope if performed?

        return scope if from.nil? && to.nil?

        scope = scope.joins(:party_event) unless scope.joins_values.include?(:party_event)
        scope = scope.where(party_events: { held_on: from.. }) if from
        scope = scope.where(party_events: { held_on: ..to }) if to
        scope
      end

      def parse_filter_date(key)
        raw = params[key].to_s
        return nil if raw.blank?

        Date.iso8601(raw)
      rescue ArgumentError
        render_error(400, "invalid_filter",
                     "Filtre « #{key} » invalide : « #{raw} ». Format attendu : YYYY-MM-DD.")
        nil
      end

      # `paid` s'appuie sur `payment_status` — le seul axe qui dit si l'argent est
      # réellement arrivé (Stripe, portefeuille, liquide/virement pointé), par
      # opposition au `status` logistique.
      def apply_paid_filter(scope)
        raw = params[:paid].to_s
        return scope if raw.blank?

        case raw
        when "true"  then scope.where(payment_status: Order.payment_statuses[:paid])
        when "false" then scope.where.not(payment_status: Order.payment_statuses[:paid])
        else
          render_error(400, "invalid_filter",
                       "Filtre « paid » invalide : « #{raw} ». Valeurs acceptées : true, false.")
          scope
        end
      end
    end
  end
end
