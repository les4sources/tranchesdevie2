# frozen_string_literal: true

module Api
  module V1
    # Builds an OpenAPI 3.1 document from the ResourceCatalog so the machine spec
    # never drifts from the discovery endpoint or the markdown guide.
    module OpenapiSpec
      module_function

      def build(base_url)
        {
          openapi: "3.1.0",
          info: {
            title: "Tranches de Vie — API privée (agents)",
            version: ResourceCatalog::VERSION,
            description: "API JSON privée, en lecture seule, destinée aux agents IA. " \
                         "Authentification : en-tête « Authorization: Bearer <TRANCHESDEVIE_API_KEY> ». " \
                         "Conventions : argent en cents et en euros, enums en chaînes nommées, dates ISO 8601, " \
                         "pagination via ?page=/?per_page=. Certaines ressources contiennent des données personnelles (PII)."
          },
          servers: [ { url: "#{base_url}/api/v1" } ],
          security: [ { bearerAuth: [] } ],
          tags: ResourceCatalog.resources.map { |r| { name: r[:key], description: r[:description] } },
          paths: paths,
          components: {
            securitySchemes: {
              bearerAuth: {
                type: "http", scheme: "bearer",
                description: "Clé partagée TRANCHESDEVIE_API_KEY (variable d'environnement côté serveur)."
              }
            },
            schemas: schemas,
            responses: {
              "Unauthorized" => { description: "Clé API manquante ou invalide.", content: error_content },
              "NotFound" => { description: "Ressource introuvable.", content: error_content }
            }
          }
        }
      end

      def paths
        result = {
          "/" => { get: { tags: [ "discovery" ], summary: "Découverte de l'API (point d'entrée agent)", responses: { "200" => { description: "OK" }, "401" => ref_response("Unauthorized") } } },
          "/openapi.json" => { get: { tags: [ "discovery" ], summary: "Cette spec OpenAPI", responses: { "200" => { description: "OK" } } } },
          "/docs" => { get: { tags: [ "discovery" ], summary: "Guide markdown lisible par agent", responses: { "200" => { description: "OK", content: { "text/markdown" => {} } } } } },
          "/stats" => { get: stats_op }
        }

        ResourceCatalog.resources.each do |r|
          collection = "/#{r[:key]}"
          if r[:collection]
            result[collection] = { get: list_op(r) }
            result["#{collection}/{id}"] = { get: show_op(r) }
          else
            result[collection] = { get: show_op(r) }
          end
        end

        result
      end

      def schemas
        base = ResourceCatalog.resources.each_with_object({}) do |r, acc|
          acc[schema_name(r)] = {
            type: "object",
            description: r[:description],
            properties: r[:fields].transform_values { |desc| property(desc) }
          }
        end
        base.merge(
          "Error" => {
            type: "object",
            properties: {
              "error" => {
                type: "object",
                properties: {
                  "status" => { type: "integer" },
                  "code" => { type: "string" },
                  "message" => { type: "string" },
                  "documentation_url" => { type: "string" }
                }
              }
            }
          },
          "Pagination" => {
            type: "object",
            properties: {
              "page" => { type: "integer" },
              "per_page" => { type: "integer" },
              "total_count" => { type: "integer" },
              "total_pages" => { type: "integer" }
            }
          }
        )
      end

      def property(description)
        type =
          case description
          when /\Ainteger/ then "integer"
          when /\Anumber/ then "number"
          when /\Aboolean/ then "boolean"
          when /\Aarray/ then "array"
          when /\Aobject/ then "object"
          else "string"
          end

        prop = { description: description }
        if type == "array"
          prop[:type] = "array"
          prop[:items] = { type: "object" }
        else
          prop[:type] = type
        end
        prop
      end

      def list_op(resource)
        {
          tags: [ resource[:key] ],
          summary: "Lister : #{resource[:title]}",
          description: resource[:description],
          parameters: pagination_params + filter_params(resource),
          responses: {
            "200" => {
              description: "OK",
              content: {
                "application/json" => {
                  schema: {
                    type: "object",
                    properties: {
                      "data" => { type: "array", items: ref(resource) },
                      "meta" => { "$ref" => "#/components/schemas/Pagination" },
                      "_links" => { type: "object" }
                    }
                  }
                }
              }
            },
            "401" => ref_response("Unauthorized")
          }
        }
      end

      def show_op(resource)
        {
          tags: [ resource[:key] ],
          summary: "Détail : #{resource[:singular]}",
          description: resource[:description],
          parameters: resource[:collection] ? [ { name: "id", in: "path", required: true, schema: { type: "integer" } } ] : [],
          responses: {
            "200" => {
              description: "OK",
              content: {
                "application/json" => {
                  schema: { type: "object", properties: { "data" => ref(resource), "_links" => { type: "object" } } }
                }
              }
            },
            "401" => ref_response("Unauthorized"),
            "404" => ref_response("NotFound")
          }
        }
      end

      def stats_op
        {
          tags: [ "stats" ],
          summary: "Statistiques de ventes entre deux dates",
          parameters: [
            { name: "start_date", in: "query", required: false, description: "Date de début (YYYY-MM-DD, défaut J-30).", schema: { type: "string", format: "date" } },
            { name: "end_date", in: "query", required: false, description: "Date de fin (YYYY-MM-DD, défaut aujourd'hui).", schema: { type: "string", format: "date" } }
          ],
          responses: { "200" => { description: "OK" }, "401" => ref_response("Unauthorized") }
        }
      end

      def pagination_params
        [
          { name: "page", in: "query", required: false, schema: { type: "integer", default: 1 } },
          { name: "per_page", in: "query", required: false, schema: { type: "integer", default: 25, maximum: 100 } }
        ]
      end

      def filter_params(resource)
        (resource[:filters] || {}).map do |name, description|
          { name: name.to_s, in: "query", required: false, description: description, schema: { type: "string" } }
        end
      end

      def schema_name(resource)
        resource[:singular].split("_").map(&:capitalize).join
      end

      def ref(resource)
        { "$ref" => "#/components/schemas/#{schema_name(resource)}" }
      end

      def ref_response(name)
        { "$ref" => "#/components/responses/#{name}" }
      end

      def error_content
        { "application/json" => { schema: { "$ref" => "#/components/schemas/Error" } } }
      end
    end
  end
end
