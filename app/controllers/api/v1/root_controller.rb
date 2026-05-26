# frozen_string_literal: true

module Api
  module V1
    # Agent entry points: self-describing discovery index, OpenAPI spec, markdown guide.
    class RootController < BaseController
      def index
        base = request.base_url
        render json: {
          data: {
            name: "Tranches de Vie — API privée (agents)",
            version: ResourceCatalog::VERSION,
            description: "API HTTP JSON privée, en lecture seule, pour agents IA. " \
                         "Suivez les liens et lisez la documentation ci-dessous pour tout découvrir.",
            authentication: {
              scheme: "Bearer",
              header: "Authorization: Bearer <TRANCHESDEVIE_API_KEY>",
              note: "Clé partagée unique. 401 si absente/invalide, 503 si non configurée côté serveur."
            },
            conventions: ResourceCatalog::CONVENTIONS,
            resources: resource_index(base),
            stats: {
              url: "#{base}/api/v1/stats",
              description: "Statistiques de ventes entre deux dates (?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD)."
            }
          },
          _links: {
            self: "#{base}/api/v1",
            openapi: "#{base}/api/v1/openapi.json",
            documentation: "#{base}/api/v1/docs"
          }
        }
      end

      def openapi
        render json: OpenapiSpec.build(request.base_url)
      end

      def docs
        render plain: ApiGuide.markdown(request.base_url), content_type: "text/markdown"
      end

      private

      def resource_index(base)
        ResourceCatalog.resources.map do |resource|
          {
            name: resource[:key],
            title: resource[:title],
            description: resource[:description],
            contains_pii: resource[:pii],
            collection: resource[:collection],
            url: "#{base}#{ResourceCatalog.collection_path(resource)}",
            item_url: "#{base}#{ResourceCatalog.item_path(resource)}",
            filters: resource[:filters]&.keys,
            fields: resource[:fields].keys
          }.compact
        end
      end
    end
  end
end
