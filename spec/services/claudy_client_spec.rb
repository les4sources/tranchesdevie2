require 'rails_helper'

# Enveloppe HTTP de l'API de notes de claudy (#259). Aucun appel réseau réel :
# tout est stubé par WebMock.
RSpec.describe ClaudyClient do
  let(:api_url) { 'https://claudy.test' }
  let(:token) { 'tok_claudy' }
  let(:notes_url) { "#{api_url}/api/v1/notes" }
  let(:payload) { { date: Date.new(2026, 9, 18), color: 'orange', external_ref: 'tranchesdevie-order-42', body: "Pizza Party privée\nSoirée : Michael Hulet - 18 personnes" } }

  subject(:client) { described_class.new(api_url: api_url, api_token: token) }

  describe '#create_note' do
    it "POSTe vers /api/v1/notes, avec le bearer token et le corps encapsulé sous la clé note" do
      stub = stub_request(:post, notes_url)
             .with(headers: { 'Authorization' => "Bearer #{token}" },
                   body: { note: payload }.to_json)
             .to_return(status: 201, body: { id: 77 }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(client.create_note(payload)).to eq(77)
      expect(stub).to have_been_requested
    end

    it "accepte une réponse enveloppée sous la clé note" do
      stub_request(:post, notes_url).to_return(status: 201, body: { note: { id: 88 } }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(client.create_note(payload)).to eq(88)
    end

    it "propage une erreur serveur au job, qui la retentera" do
      stub_request(:post, notes_url).to_return(status: 500, body: 'boom')

      expect { client.create_note(payload) }.to raise_error(ClaudyClient::Error, /500/)
    end

    it "propage un timeout réseau" do
      stub_request(:post, notes_url).to_timeout

      expect { client.create_note(payload) }.to raise_error(ClaudyClient::Error)
    end
  end

  describe '#delete_note' do
    it "DELETE vers /api/v1/notes/<id>" do
      stub = stub_request(:delete, "#{notes_url}/77")
             .with(headers: { 'Authorization' => "Bearer #{token}" })
             .to_return(status: 204)

      expect(client.delete_note(77)).to be true
      expect(stub).to have_been_requested
    end

    it "traite un 404 comme un succès — la note a déjà disparu côté claudy" do
      stub_request(:delete, "#{notes_url}/77").to_return(status: 404, body: '{"error":"not found"}')

      expect(client.delete_note(77)).to be true
    end

    it "propage une erreur serveur" do
      stub_request(:delete, "#{notes_url}/77").to_return(status: 500, body: 'boom')

      expect { client.delete_note(77) }.to raise_error(ClaudyClient::Error, /500/)
    end
  end

  describe "sans CLAUDY_API_TOKEN" do
    subject(:client) { described_class.new(api_url: api_url, api_token: nil) }

    around do |example|
      original = ENV['CLAUDY_API_TOKEN']
      ENV.delete('CLAUDY_API_TOKEN')
      example.run
      ENV['CLAUDY_API_TOKEN'] = original
    end

    it "n'émet aucune requête et ne lève rien (no-op silencieux)" do
      expect(client).not_to be_configured
      expect { expect(client.create_note(payload)).to be_nil }.not_to raise_error
      expect { expect(client.delete_note(77)).to be_nil }.not_to raise_error

      expect(a_request(:any, /claudy/)).not_to have_been_made
    end
  end

  describe "URL de base" do
    it "retombe sur l'application des 4 Sources par défaut" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('CLAUDY_API_URL').and_return(nil)
      allow(ENV).to receive(:[]).with('CLAUDY_API_TOKEN').and_return(token)

      stub = stub_request(:post, 'https://app.les4sources.be/api/v1/notes')
             .to_return(status: 201, body: { id: 9 }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.new.create_note(payload)
      expect(stub).to have_been_requested
    end
  end
end
