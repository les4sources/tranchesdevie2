# frozen_string_literal: true

module Api
  module V1
    # Foundation for the private, read-only agent API.
    #
    # Inherits from ActionController::API (not ApplicationController) so it never
    # pulls in cookie sessions, CSRF, or CustomerAuthentication. Auth is a single
    # shared Bearer token read from ENV["TRANCHESDEVIE_API_KEY"].
    class BaseController < ActionController::API
      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      before_action :authenticate_api_request!

      rescue_from ActiveRecord::RecordNotFound do
        render_error(404, "not_found", "Ressource introuvable.")
      end

      # Catch-all for unknown paths under /api/v1 (GET only — the API is read-only).
      def not_found_route
        render_error(
          404,
          "not_found",
          "Cet endpoint n'existe pas. Voir GET /api/v1 pour la liste des ressources disponibles."
        )
      end

      private

      def authenticate_api_request!
        expected = ENV["TRANCHESDEVIE_API_KEY"].to_s

        if expected.empty?
          return render_error(
            503,
            "api_key_not_configured",
            "L'API n'est pas configurée : la variable d'environnement TRANCHESDEVIE_API_KEY est absente côté serveur."
          )
        end

        provided = bearer_token.to_s
        return if provided.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)

        render_error(
          401,
          "unauthorized",
          "Clé API manquante ou invalide. Envoyez l'en-tête « Authorization: Bearer <TRANCHESDEVIE_API_KEY> »."
        )
      end

      def bearer_token
        request.authorization.to_s[/\ABearer\s+(.+)\z/i, 1]
      end

      def serializer_context(detail: false)
        { host: request.base_url, detail: detail }
      end

      def render_resource(object, serializer, links: {})
        render json: {
          data: serializer.one(object, serializer_context(detail: true)),
          _links: base_links.merge(links)
        }
      end

      def render_collection(scope, serializer, links: {})
        records, meta = paginate(scope)
        render json: {
          data: serializer.many(records, serializer_context),
          meta: meta,
          _links: base_links.merge(links).merge(pagination_links(meta))
        }
      end

      def paginate(scope)
        page = params[:page].to_i
        page = 1 if page < 1
        per_page = params[:per_page].to_i
        per_page = DEFAULT_PER_PAGE if per_page < 1
        per_page = MAX_PER_PAGE if per_page > MAX_PER_PAGE

        total = scope.except(:includes, :preload, :eager_load).count
        total = total.size if total.is_a?(Hash)
        records = scope.limit(per_page).offset((page - 1) * per_page)

        meta = {
          page: page,
          per_page: per_page,
          total_count: total,
          total_pages: (total.to_f / per_page).ceil
        }
        [ records, meta ]
      end

      def pagination_links(meta)
        links = {}
        query = request.query_parameters
        links[:next] = "#{request.path}?#{query.merge('page' => meta[:page] + 1).to_query}" if meta[:page] < meta[:total_pages]
        links[:prev] = "#{request.path}?#{query.merge('page' => meta[:page] - 1).to_query}" if meta[:page] > 1
        links
      end

      def base_links
        { self: request.original_fullpath, documentation: "/api/v1/docs" }
      end

      def render_error(status_code, code, message)
        render json: {
          error: {
            status: status_code,
            code: code,
            message: message,
            documentation_url: "#{request.base_url}/api/v1/docs"
          }
        }, status: status_code
      end
    end
  end
end
