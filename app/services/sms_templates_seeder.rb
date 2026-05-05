class SmsTemplatesSeeder
  CONFIG_PATH = Rails.root.join("config", "sms_templates.yml")

  def self.call(logger: Rails.logger)
    new(logger: logger).call
  end

  def initialize(logger: Rails.logger)
    @logger = logger
  end

  def call
    templates_config.each { |config| sync_template(config) }
  end

  private

  attr_reader :logger

  def templates_config
    YAML.load_file(CONFIG_PATH).fetch("templates")
  end

  def sync_template(config)
    template = SmsTemplate.find_or_initialize_by(name: config.fetch("name"))
    template.assign_attributes(
      category: config.fetch("category"),
      language: config.fetch("language"),
      body: config.fetch("body"),
      variables: config.fetch("variables", [])
    )

    if template.synced?
      status = remote_status(template)
      if status && status != "DRAFT"
        logger.info("[sms_templates] skip update: #{template.name} (statut #{status} côté Sent.dm)")
      else
        remote_update(template)
      end
    else
      remote_create(template)
    end

    template.synced_at = Time.current
    template.save!
    logger.info("[sms_templates] synchronisé: #{template.name} (#{template.external_id})")
  end

  # Sent.dm refuse l'`update` sur un template qui n'est plus en DRAFT (PENDING,
  # APPROVED, REJECTED). Pour rester idempotent, on ne ré-applique le YAML local
  # que sur les drafts.
  def remote_status(template)
    response = SentDmClient.retrieve_template(template.external_id)
    response&.data&.status
  rescue StandardError => e
    logger.warn("[sms_templates] impossible de lire le statut de #{template.name}: #{e.class} #{e.message[0, 100]}")
    nil
  end

  def remote_create(template)
    response = SentDmClient.create_template(
      name: template.name,
      category: template.category,
      language: template.language,
      body: template.body,
      variables: template.variables
    )
    template.external_id = extract_id(response)
  end

  def remote_update(template)
    SentDmClient.update_template(
      id: template.external_id,
      name: template.name,
      category: template.category,
      language: template.language,
      body: template.body,
      variables: template.variables
    )
  end

  # `create_template` renvoie une réponse HTTParty (l'API REST n'est pas
  # exposée par le SDK pour le champ `name`).
  def extract_id(response)
    payload = response.parsed_response
    payload.dig("data", "id") if payload.is_a?(Hash)
  end
end
