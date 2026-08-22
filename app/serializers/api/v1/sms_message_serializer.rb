# frozen_string_literal: true

module Api
  module V1
    class SmsMessageSerializer < BaseSerializer
      def as_json
        {
          id: object.id,
          direction: object.direction,
          kind: object.kind,
          to_e164: object.to_e164,
          from_e164: object.from_e164,
          body: object.body,
          baked_on: object.baked_on,
          customer_id: object.customer_id,
          external_id: object.external_id,
          sent_at: iso(object.sent_at),
          created_at: iso(object.created_at),
          updated_at: iso(object.updated_at),
          _links: { self: path("sms_messages", object.id) }
        }
      end
    end
  end
end
