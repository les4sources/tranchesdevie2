class SentDmClient
  # Verrouille tous les envois sur SMS uniquement. Sans ce paramètre, Sent.dm
  # bascule en auto-detect et peut router via WhatsApp si le destinataire en
  # dispose. Ne PAS modifier sans alignement explicite avec le métier.
  ALLOWED_CHANNELS = [ "sms" ].freeze

  class ConfigurationError < StandardError; end
  class TemplateNotSyncedError < StandardError; end
  class APIError < StandardError; end

  class << self
    def send_message(template_name:, to:, parameters: {})
      template = SmsTemplate.find_by(name: template_name.to_s)
      raise TemplateNotSyncedError, "Template '#{template_name}' introuvable en base" unless template
      raise TemplateNotSyncedError, "Template '#{template_name}' non synchronisé avec Sent.dm" unless template.synced?

      client.messages.send_(
        to: [ to ],
        template: { id: template.external_id, parameters: parameters.transform_keys(&:to_sym) },
        channel: ALLOWED_CHANNELS,
        sandbox: send_sandbox?
      )
    end

    # Le SDK 0.18 ne permet pas de définir le `name` à la création (champ accepté
    # par l'API REST mais non exposé). On bascule sur un appel HTTP direct pour
    # garantir que le template est créé avec un name stable.
    #
    # Les templates ne sont PAS créés en sandbox : ce sont des artefacts de
    # configuration partagés entre environnements. En sandbox, Sent.dm simule la
    # création et renvoie un UUID fictif sans persister, ce qui rend l'envoi
    # ultérieur impossible.
    def create_template(name:, category:, language:, body:, variables:)
      response = HTTParty.post(
        "#{api_base_url}/v3/templates",
        headers: rest_headers,
        body: {
          name: name,
          category: category,
          language: language,
          definition: build_definition(body: body, variables: variables),
          sandbox: false
        }.to_json
      )
      raise APIError, "Sent.dm create_template a échoué (#{response.code}): #{response.body}" unless response.success?
      response
    end

    def update_template(id:, name:, category:, language:, body:, variables:)
      client.templates.update(
        id,
        name: name,
        category: category,
        language: language,
        definition: build_definition(body: body, variables: variables),
        sandbox: false
      )
    end

    def retrieve_template(id)
      client.templates.retrieve(id)
    end

    def reset!
      @client = nil
    end

    private

    def client
      raise ConfigurationError, "SENT_DM_API_KEY manquant" if api_key.blank?

      @client ||= Sentdm::Client.new(api_key: api_key)
    end

    def api_key
      ENV["SENT_DM_API_KEY"]
    end

    def api_base_url
      ENV.fetch("SENT_DM_API_BASE_URL", "https://api.sent.dm")
    end

    def rest_headers
      {
        "Content-Type" => "application/json",
        "x-api-key" => api_key
      }
    end

    # Sandbox d'envoi : actif hors production pour ne pas dépenser de crédit ni
    # consommer le quota carrier pendant le développement et les tests.
    def send_sandbox?
      !Rails.env.production?
    end

    # Sent.dm n'accepte pas la clé `sms` seule (erreur VALIDATION_001 :
    # "either multiChannel OR both sms and whatsapp"). On utilise donc
    # `multiChannel` ; le filtrage SMS-only est garanti par `channel: ["sms"]`
    # au moment de l'envoi (cf. send_message).
    def build_definition(body:, variables:)
      {
        body: {
          multiChannel: {
            type: "text",
            template: body,
            variables: variables.map { |v| build_variable(v) }
          }
        },
        definitionVersion: "1.0"
      }
    end

    def build_variable(variable)
      data = variable.with_indifferent_access
      {
        id: data.fetch(:id),
        name: data.fetch(:name),
        type: "variable",
        props: {
          variableType: "text",
          sample: data[:sample].to_s
        }
      }
    end
  end
end
