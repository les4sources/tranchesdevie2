# frozen_string_literal: true

module Api
  module V1
    # Single source of truth describing every resource the agent API exposes.
    #
    # The discovery endpoint (GET /api/v1), the OpenAPI document
    # (GET /api/v1/openapi.json) and the markdown guide (GET /api/v1/docs) are all
    # generated from this catalog, so they can never drift apart. This is the
    # "self-describing" core: an agent learns the whole API from the root response.
    module ResourceCatalog
      module_function

      VERSION = "1.0.0"
      BASE_PATH = "/api/v1"

      CONVENTIONS = [
        "Authentification : en-tête « Authorization: Bearer <TRANCHESDEVIE_API_KEY> » sur chaque requête.",
        "Lecture seule : seules des requêtes GET existent. Aucune écriture n'est possible.",
        "Enveloppe succès : { \"data\": ..., \"meta\": {pagination}, \"_links\": {navigation} }.",
        "Enveloppe erreur : { \"error\": { \"status\", \"code\", \"message\", \"documentation_url\" } }.",
        "Pagination : paramètres ?page= (défaut 1) et ?per_page= (défaut 25, max 100) sur les collections.",
        "Argent : exposé en cents (champs *_cents) ET en euros (champs *_euros).",
        "Enums : sérialisés en chaînes nommées (ex. status=\"paid\"), jamais en entiers.",
        "Dates/heures : format ISO 8601.",
        "Navigation : suivez les liens du champ _links plutôt que de deviner les URLs."
      ].freeze

      # Each entry documents one resource. :collection=false marks a singleton.
      RESOURCES = [
        {
          key: "products", singular: "product", title: "Produits", pii: false, collection: true,
          description: "Catalogue : pains et boules de pâte, avec leurs variantes, images et composition en farines.",
          fields: {
            id: "integer", name: "string", short_name: "string|null", description: "string|null",
            category: "enum: breads|dough_balls", channel: "enum: store|admin", active: "boolean",
            position: "integer", flour_quantity: "integer|null (grammes)",
            flour_composition: "string (libellé farines)", created_at: "datetime", updated_at: "datetime",
            variants: "array<product_variant> (détail)", images: "array<image> (détail)"
          }
        },
        {
          key: "product_variants", singular: "product_variant", title: "Variantes de produit", pii: false, collection: true,
          description: "Formats/tailles vendables d'un produit, avec prix, type de moule, ingrédients et restrictions de groupe.",
          fields: {
            id: "integer", product_id: "integer", name: "string", price_cents: "integer", price_euros: "number",
            active: "boolean", channel: "enum: store|admin", flour_quantity: "integer|null (grammes)",
            mold_type: "object|null", restricted: "boolean", image_url: "string|null",
            ingredients: "array (détail)", restricted_group_ids: "array<integer> (détail)",
            availabilities: "array (détail)", created_at: "datetime", updated_at: "datetime"
          }
        },
        {
          key: "bake_days", singular: "bake_day", title: "Jours de fournée", pii: false, collection: true,
          description: "Dates de cuisson (mardi/vendredi) avec deadline de commande, jour de marché, artisans et capacité de production.",
          fields: {
            id: "integer", baked_on: "date", cut_off_at: "datetime", can_order: "boolean",
            market_day: "boolean", internal_note: "string|null", total_breads_count: "integer",
            total_sales_euros: "number", oven_capacity_grams: "integer", artisans: "array (détail)",
            capacity: "object {molds,kneader,oven,fill_percentage,fully_booked} (détail)",
            created_at: "datetime", updated_at: "datetime"
          },
          sub: [ { rel: "orders", path_suffix: "orders", description: "Commandes de ce jour de fournée." } ]
        },
        {
          key: "customers", singular: "customer", title: "Clients", pii: true, collection: true,
          description: "Clients identifiés par téléphone E.164. CONTIENT DES DONNÉES PERSONNELLES (téléphone, email, nom).",
          fields: {
            id: "integer", first_name: "string", last_name: "string|null", full_name: "string",
            phone_e164: "string|null (PII)", email: "string|null (PII)", billable: "boolean",
            sms_opt_out: "boolean", email_opt_out: "boolean", effective_discount_percent: "integer",
            groups: "array<group>", wallet_balance_cents: "integer|null", wallet_balance_euros: "number|null",
            created_at: "datetime", updated_at: "datetime"
          },
          sub: [ { rel: "orders", path_suffix: "orders", description: "Commandes du client." } ]
        },
        {
          key: "orders", singular: "order", title: "Commandes", pii: true, collection: true,
          description: "Commandes clients pour un jour de fournée. Liées à un client (PII) et à des lignes de commande.",
          fields: {
            id: "integer", order_number: "string (TV-YYYYMMDD-NNNN)",
            status: "enum: pending|paid|ready|picked_up|no_show|cancelled|unpaid|planned",
            source: "enum: checkout|calendar|admin", total_cents: "integer", total_euros: "number",
            requires_invoice: "boolean", payment_method: "enum: stripe|wallet|null",
            payment_received: "boolean", paid_at: "datetime|null", customer_id: "integer",
            bake_day_id: "integer", items: "array<order_item>", payment: "object|null (détail)",
            created_at: "datetime", updated_at: "datetime"
          },
          filters: {
            status: "Filtrer par statut (ex. ?status=paid).",
            source: "Filtrer par source (ex. ?source=checkout).",
            bake_day_id: "Filtrer par jour de fournée (ex. ?bake_day_id=12)."
          }
        },
        {
          key: "payments", singular: "payment", title: "Paiements", pii: true, collection: true,
          description: "Paiements Stripe rattachés aux commandes. Contient les identifiants PaymentIntent Stripe.",
          fields: {
            id: "integer", order_id: "integer", stripe_payment_intent_id: "string",
            status: "enum: succeeded|failed|refunded",
            stripe_fee_cents: "integer|null", stripe_fee_euros: "number|null",
            created_at: "datetime", updated_at: "datetime"
          }
        },
        {
          key: "wallets", singular: "wallet", title: "Portefeuilles", pii: true, collection: true,
          description: "Solde prépayé par client (un par client). Contient le solde et le seuil d'alerte.",
          fields: {
            id: "integer", customer_id: "integer", balance_cents: "integer", balance_euros: "number",
            low_balance_threshold_cents: "integer", low_balance: "boolean",
            available_balance_cents: "integer (solde moins commandes planifiées)",
            transactions: "array<wallet_transaction> (détail)", created_at: "datetime", updated_at: "datetime"
          },
          sub: [ { rel: "transactions", path_suffix: "transactions", description: "Transactions du portefeuille." } ]
        },
        {
          key: "wallet_transactions", singular: "wallet_transaction", title: "Transactions de portefeuille", pii: true, collection: true,
          description: "Mouvements de solde : recharges, débits de commande, remboursements.",
          fields: {
            id: "integer", wallet_id: "integer", order_id: "integer|null",
            transaction_type: "enum: top_up|order_debit|order_refund", amount_cents: "integer",
            amount_euros: "number", description: "string|null", stripe_payment_intent_id: "string|null",
            created_at: "datetime", updated_at: "datetime"
          }
        },
        {
          key: "groups", singular: "group", title: "Groupes (remises)", pii: false, collection: true,
          description: "Paliers de remise client. La remise la plus élevée s'applique.",
          fields: { id: "integer", name: "string", discount_percent: "integer", customers_count: "integer", created_at: "datetime", updated_at: "datetime" }
        },
        {
          key: "flours", singular: "flour", title: "Farines", pii: false, collection: true,
          description: "Types de farine, avec limite de pétrin (planification de production).",
          fields: { id: "integer", name: "string", position: "integer", kneader_limit_grams: "integer|null", created_at: "datetime", updated_at: "datetime" }
        },
        {
          key: "mold_types", singular: "mold_type", title: "Types de moules", pii: false, collection: true,
          description: "Types de moules avec limite d'unités par jour de fournée.",
          fields: { id: "integer", name: "string", limit: "integer", position: "integer", created_at: "datetime", updated_at: "datetime" }
        },
        {
          key: "ingredients", singular: "ingredient", title: "Ingrédients", pii: false, collection: true,
          description: "Ingrédients utilisés dans les variantes.",
          fields: { id: "integer", name: "string", unit_type: "enum: weight|piece", unit_label: "string", position: "integer", created_at: "datetime", updated_at: "datetime" }
        },
        {
          key: "artisans", singular: "artisan", title: "Artisans", pii: false, collection: true,
          description: "Boulangers assignables aux jours de fournée.",
          fields: { id: "integer", name: "string", active: "boolean", created_at: "datetime", updated_at: "datetime" }
        },
        {
          key: "production_setting", singular: "production_setting", title: "Paramètres de production", pii: false, collection: false,
          description: "Réglage singleton : capacités du four (jour normal et jour de marché).",
          fields: { id: "integer", oven_capacity_grams: "integer", market_day_oven_capacity_grams: "integer", created_at: "datetime", updated_at: "datetime" }
        },
        {
          key: "sms_messages", singular: "sms_message", title: "Messages SMS", pii: true, collection: true,
          description: "Journal des SMS entrants/sortants. CONTIENT DES DONNÉES PERSONNELLES (numéros, contenu).",
          fields: {
            id: "integer", direction: "enum: outbound|inbound", kind: "enum: confirmation|ready|refund|otp|other",
            to_e164: "string (PII)", from_e164: "string (PII)", body: "string (PII)", baked_on: "date|null",
            customer_id: "integer|null", external_id: "string|null", sent_at: "datetime|null",
            created_at: "datetime", updated_at: "datetime"
          }
        },
        {
          key: "email_messages", singular: "email_message", title: "Messages e-mail", pii: true, collection: true,
          description: "Journal des e-mails. CONTIENT DES DONNÉES PERSONNELLES (adresses, sujet, corps HTML).",
          fields: {
            id: "integer", direction: "enum: outbound|inbound", kind: "enum: confirmation|otp|other",
            to_email: "string (PII)", from_email: "string (PII)", subject: "string|null", body_html: "string (PII)",
            message_id: "string|null", customer_id: "integer|null", order_id: "integer|null",
            sent_at: "datetime|null", created_at: "datetime", updated_at: "datetime"
          }
        }
      ].freeze

      def resources
        RESOURCES
      end

      def find(key)
        RESOURCES.find { |r| r[:key] == key }
      end

      def collection_path(resource)
        "#{BASE_PATH}/#{resource[:key]}"
      end

      def item_path(resource)
        resource[:collection] ? "#{collection_path(resource)}/{id}" : collection_path(resource)
      end
    end
  end
end
