# Enveloppe HTTP de l'API de notes de claudy — l'application des 4 Sources, dont
# le calendrier est la vue partagée de ce qui se passe au Domaine (#259).
#
# Deux appels seulement : poser une note (POST, upsert côté claudy sur
# `external_ref`) et la retirer (DELETE, soft-delete). Même esprit que
# SlackService pour l'appel sortant : timeouts explicites, erreur typée.
#
# Sans `CLAUDY_API_TOKEN`, chaque appel est un NO-OP SILENCIEUX : rien ne part,
# une ligne de log explique pourquoi, aucune exception ne remonte. C'est l'état
# du poste de développement et de la CI — l'application doit s'y comporter
# exactement comme avant.
class ClaudyClient
  class Error < StandardError; end

  DEFAULT_API_URL = "https://app.les4sources.be"
  NOTES_PATH = "/api/v1/notes"
  TIMEOUT_SECONDS = 5

  # Erreurs réseau à remonter au job, qui les retentera avec backoff.
  NETWORK_ERRORS = [ HTTParty::Error, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED ].freeze

  def self.create_note(payload)
    new.create_note(payload)
  end

  def self.delete_note(note_id)
    new.delete_note(note_id)
  end

  def initialize(api_url: nil, api_token: nil)
    @api_url = (api_url || ENV["CLAUDY_API_URL"]).presence || DEFAULT_API_URL
    @api_token = (api_token || ENV["CLAUDY_API_TOKEN"]).presence
  end

  def configured?
    @api_token.present?
  end

  # Pose (ou met à jour) une note. Renvoie l'identifiant claudy de la note, ou
  # nil si le client n'est pas configuré.
  def create_note(payload)
    return log_skip("création de note") unless configured?

    response = request { HTTParty.post(notes_url, **options(body: { note: payload }.to_json)) }

    unless response.success?
      raise Error, "POST #{NOTES_PATH} a échoué : #{response.code} - #{response.body}"
    end

    extract_id(response)
  end

  # Retire une note. Un 404 vaut succès : la note a déjà disparu côté claudy
  # (suppression manuelle par exemple), le résultat voulu est atteint.
  def delete_note(note_id)
    return log_skip("suppression de note") unless configured?

    response = request { HTTParty.delete("#{notes_url}/#{note_id}", **options) }
    return true if response.success? || response.code == 404

    raise Error, "DELETE #{NOTES_PATH}/#{note_id} a échoué : #{response.code} - #{response.body}"
  end

  private

  def notes_url
    "#{@api_url.chomp('/')}#{NOTES_PATH}"
  end

  def options(body: nil)
    opts = {
      headers: {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "Authorization" => "Bearer #{@api_token}"
      },
      timeout: TIMEOUT_SECONDS
    }
    opts[:body] = body if body
    opts
  end

  def request
    yield
  rescue *NETWORK_ERRORS => e
    raise Error, "Appel à claudy impossible : #{e.class} - #{e.message}"
  end

  # claudy renvoie la note créée ; on accepte l'objet nu comme une enveloppe
  # `note` / `data`, pour ne pas dépendre d'un détail de sérialisation.
  def extract_id(response)
    parsed = response.parsed_response
    return nil unless parsed.is_a?(Hash)

    id = parsed["id"] || parsed.dig("note", "id") || parsed.dig("data", "id")
    raise Error, "Réponse de claudy sans identifiant de note : #{response.body}" if id.blank?

    id
  end

  def log_skip(action)
    Rails.logger.info("ClaudyClient: CLAUDY_API_TOKEN absent — #{action} ignorée (no-op).")
    nil
  end
end
