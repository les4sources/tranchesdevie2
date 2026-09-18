# frozen_string_literal: true

module Api
  module V1
    class OrderSerializer < BaseSerializer
      def as_json
        data = {
          id: object.id,
          order_number: object.order_number,
          status: object.status,
          source: object.source,
          total_cents: object.total_cents,
          total_euros: object.total_euros,
          requires_invoice: object.requires_invoice,
          payment_method: object.payment_method,
          payment_received: object.payment_received?,
          paid_at: iso(object.paid_at),
          customer_id: object.customer_id,
          bake_day_id: object.bake_day_id,
          pickup_location_id: object.pickup_location_id,
          pickup_location: pickup_location_summary,
          party: party_summary,
          customer: customer_summary,
          cancelled: object.cancelled?,
          refunded: object.payment_refunded?,
          refunded_at: iso(refunded_at),
          items: object.order_items.map { |item| OrderItemSerializer.new(item, context).as_json },
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("orders", object.id),
            customer: path("customers", object.customer_id),
            bake_day: path("bake_days", object.bake_day_id),
            pickup_location: path("pickup_locations", object.pickup_location_id)
          }
        }

        data[:payment] = PaymentSerializer.one(object.payment, context) if detail?
        data
      end

      private

      # Résumé du lieu de retrait, inclus directement pour éviter un aller-retour
      # à l'agent sur le cas le plus courant (savoir où va la commande).
      def pickup_location_summary
        location = object.pickup_location
        return nil unless location

        { id: location.id, name: location.name, description: location.description }
      end

      # Résumé de la Pizza party, pour que Claudy rattache une party à un séjour
      # sans rappeler l'API une fois par commande (#290). `null` pour toute
      # commande sans événement party.
      def party_summary
        event = object.party_event
        return nil unless event

        {
          party_event_id: event.id,
          kind: event.kind,
          held_on: event.held_on&.to_s,
          slot: event.slot,
          group_name: party_group_name,
          persons: object.party_paton_count,
          forfait: forfait?,
          admin_url: admin_party_url(event)
        }
      end

      # Le nom du groupe vient de la demande du client ; une party saisie en admin
      # n'en a pas, mais la commande, elle, peut en porter un (saisie manuelle).
      def party_group_name
        object.party_request&.group_name.presence || object.group_name.presence
      end

      # Sans demande client (party saisie en admin), le forfait se déduit des
      # lignes : c'est la seule trace qu'il en reste.
      def forfait?
        request = object.party_request
        return request.forfait? unless request.nil?

        object.order_items.any? { |item| item.product_variant.product.pizza_party_role_forfait? }
      end

      # `APP_HOST` d'abord : c'est l'hôte public de l'app, celui que la compta
      # ouvrira. Le host de la requête ne sert que de secours (dev, où APP_HOST
      # n'est pas défini).
      def admin_party_url(event)
        app_host = ENV["APP_HOST"].presence
        base = app_host ? "https://#{app_host}" : (host || "http://localhost:3000")
        "#{base}/admin/parties/#{event.id}"
      end

      # Résumé du client embarqué, même logique que `pickup_location` : un
      # sélecteur côté agent affiche un nom, pas un identifiant. CONTIENT DES
      # DONNÉES PERSONNELLES — l'API entière en expose déjà par conception.
      def customer_summary
        customer = object.customer
        return nil unless customer

        {
          id: customer.id,
          full_name: customer.full_name,
          email: customer.email,
          phone_e164: customer.phone_e164
        }
      end

      # Horodatage du remboursement abouti, sur le canal qui l'a porté : Stripe
      # (statut du paiement) ou portefeuille (transaction de recrédit).
      def refunded_at
        return object.payment.updated_at if object.payment&.refunded?

        refund = object.wallet_transactions.detect { |t| t.transaction_type == "order_refund" }
        refund&.created_at
      end
    end
  end
end
