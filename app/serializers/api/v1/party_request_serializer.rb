# frozen_string_literal: true

module Api
  module V1
    # Demande de Pizza party privée (#pizza-parties).
    #
    # Expose le récit complet d'une demande — qui, quand, ce que le groupe a
    # écrit, qui a tranché et pourquoi. Le commentaire et le motif de refus sont
    # des données personnelles assumées : un agent qui prépare une réponse au
    # client en a besoin.
    class PartyRequestSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          state: object.state,
          held_on: object.held_on&.iso8601,
          slot: object.slot,
          customer_id: object.customer_id,
          customer_note: object.customer_note,
          group_name: object.group_name,
          order_id: object.order_id,
          paton_unit_price_cents: object.paton_unit_price_cents,
          paton_unit_price_euros: euros(object.paton_unit_price_cents),
          forfait_cents: object.forfait_cents,
          forfait_euros: euros(object.forfait_cents),
          cut_off_at: iso(object.deadline_at),
          payment_prompt_at: iso(object.payment_prompt_at),
          decided_at: iso(object.decided_at),
          decided_by: object.decided_by,
          decision_reason: object.decision_reason,
          reminded_at: iso(object.reminded_at),
          public_token: object.public_token,
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: {
            self: path("party_requests", object.id),
            order: object.order_id ? path("orders", object.order_id) : nil,
            customer: path("customers", object.customer_id)
          }.compact
        }
      end
    end
  end
end
