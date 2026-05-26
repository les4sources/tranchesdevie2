# frozen_string_literal: true

module Api
  module V1
    # Generates the agent-facing markdown guide from the ResourceCatalog.
    module ApiGuide
      module_function

      def markdown(base_url)
        api = "#{base_url}/api/v1"
        lines = []

        lines << "# Tranches de Vie — API privée pour agents IA"
        lines << ""
        lines << "API HTTP JSON **en lecture seule**, conçue pour être découverte et naviguée par des agents IA " \
                 "sans connaissance préalable du schéma. Boulangerie artisanale (Belgique) : catalogue, jours de " \
                 "fournée, capacité de production, commandes, clients, finances et messages."
        lines << ""
        lines << "- **Base URL** : `#{api}`"
        lines << "- **Point d'entrée (découverte)** : `GET #{api}` — liste toutes les ressources avec leurs URLs."
        lines << "- **Spec OpenAPI 3.1** : `GET #{api}/openapi.json`"
        lines << "- **Ce guide** : `GET #{api}/docs`"
        lines << ""
        lines << "## Authentification"
        lines << ""
        lines << "Chaque requête doit porter l'en-tête suivant (clé partagée, variable d'environnement `TRANCHESDEVIE_API_KEY`) :"
        lines << ""
        lines << "```"
        lines << "Authorization: Bearer <TRANCHESDEVIE_API_KEY>"
        lines << "```"
        lines << ""
        lines << "Exemple :"
        lines << ""
        lines << "```bash"
        lines << "curl -H \"Authorization: Bearer $TRANCHESDEVIE_API_KEY\" #{api}"
        lines << "```"
        lines << ""
        lines << "Sans clé valide : `401 unauthorized`. Si la clé n'est pas configurée côté serveur : `503 api_key_not_configured`."
        lines << ""
        lines << "## Conventions"
        lines << ""
        ResourceCatalog::CONVENTIONS.each { |c| lines << "- #{c}" }
        lines << ""
        lines << "### Enveloppe de réponse"
        lines << ""
        lines << "```json"
        lines << "{ \"data\": { /* ou [ ... ] */ }, \"meta\": { \"page\": 1, \"per_page\": 25, \"total_count\": 0, \"total_pages\": 0 }, \"_links\": { \"self\": \"...\", \"next\": \"...\" } }"
        lines << "```"
        lines << ""
        lines << "### Erreurs"
        lines << ""
        lines << "```json"
        lines << "{ \"error\": { \"status\": 401, \"code\": \"unauthorized\", \"message\": \"...\", \"documentation_url\": \"#{api}/docs\" } }"
        lines << "```"
        lines << ""
        lines << "## Ressources"
        lines << ""
        ResourceCatalog.resources.each { |r| append_resource(lines, api, r) }

        lines << "## Statistiques"
        lines << ""
        lines << "`GET #{api}/stats?start_date=YYYY-MM-DD&end_date=YYYY-MM-DD`"
        lines << ""
        lines << "Renvoie le chiffre d'affaires (cents + euros), les ventes par produit, les meilleurs clients et les ventes par mois sur la période. Les dates par défaut couvrent les 30 derniers jours."
        lines << ""

        lines.join("\n")
      end

      def append_resource(lines, api, resource)
        pii = resource[:pii] ? " ⚠️ contient des données personnelles (PII)" : ""
        lines << "### `#{resource[:key]}` — #{resource[:title]}#{pii}"
        lines << ""
        lines << resource[:description]
        lines << ""
        if resource[:collection]
          lines << "- Liste : `GET #{api}/#{resource[:key]}`"
          lines << "- Détail : `GET #{api}/#{resource[:key]}/{id}`"
        else
          lines << "- `GET #{api}/#{resource[:key]}` (ressource unique / singleton)"
        end
        (resource[:filters] || {}).each { |name, desc| lines << "- Filtre `?#{name}=` — #{desc}" }
        (resource[:sub] || []).each { |s| lines << "- Sous-ressource `#{s[:rel]}` : `GET #{api}/#{resource[:key]}/{id}/#{s[:path_suffix]}` — #{s[:description]}" }
        lines << ""
        lines << "Champs :"
        lines << ""
        resource[:fields].each { |name, desc| lines << "- `#{name}` — #{desc}" }
        lines << ""
      end
    end
  end
end
