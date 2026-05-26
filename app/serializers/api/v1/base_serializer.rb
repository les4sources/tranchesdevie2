# frozen_string_literal: true

module Api
  module V1
    # Base class for read-only API serializers.
    #
    # Conventions enforced by the helpers below (documented to agents in the
    # OpenAPI spec and the markdown guide):
    #   - money is exposed in cents (`*_cents`) AND in euros (`*_euros`)
    #   - enums are serialized as their string name, never the integer value
    #   - timestamps are ISO 8601 strings
    class BaseSerializer
      attr_reader :object, :context

      def initialize(object, context = {})
        @object = object
        @context = context
      end

      # Serialize a single record (or nil).
      def self.one(object, context = {})
        return nil if object.nil?

        new(object, context).as_json
      end

      # Serialize a collection.
      def self.many(collection, context = {})
        collection.map { |record| new(record, context).as_json }
      end

      def as_json
        raise NotImplementedError, "#{self.class} must implement #as_json"
      end

      private

      def euros(cents)
        return nil if cents.nil?

        (cents / 100.0).round(2)
      end

      def iso(time)
        time&.iso8601
      end

      def host
        context[:host]
      end

      def detail?
        context[:detail]
      end

      def path(*segments)
        "/api/v1/#{segments.join('/')}"
      end

      def blob_url(attachment)
        return nil unless attachment.respond_to?(:attached?) && attachment.attached?

        Rails.application.routes.url_helpers.rails_blob_url(
          attachment,
          host: host || "http://localhost:3000"
        )
      rescue StandardError
        nil
      end
    end
  end
end
