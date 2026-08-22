# frozen_string_literal: true

module Api
  module V1
    class EmailMessageSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          direction: object.direction,
          kind: object.kind,
          to_email: object.to_email,
          from_email: object.from_email,
          subject: object.subject,
          body_html: object.body_html,
          message_id: object.message_id,
          customer_id: object.customer_id,
          order_id: object.order_id,
          sent_at: iso(object.sent_at),
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("email_messages", object.id) }
        }
      end
    end
  end
end
