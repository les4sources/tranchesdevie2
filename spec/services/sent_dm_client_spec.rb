require 'rails_helper'

RSpec.describe SentDmClient do
  let(:fake_client) { double("Sentdm::Client", messages: messages_resource, templates: templates_resource) }
  let(:messages_resource) { double("messages") }
  let(:templates_resource) { double("templates") }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("SENT_DM_API_KEY").and_return("test-key")
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("SENT_DM_API_BASE_URL", "https://api.sent.dm").and_return("https://api.sent.dm")
    allow(Sentdm::Client).to receive(:new).and_return(fake_client)
    described_class.reset!
  end

  describe '.send_message' do
    let!(:template) { create(:sms_template, name: "confirmation") }

    it 'envoie le message via le SDK avec template par external_id' do
      expect(messages_resource).to receive(:send_).with(
        to: [ "+32499999999" ],
        template: { id: template.external_id, parameters: { code: "123" } },
        channel: [ "sms" ],
        sandbox: true
      )

      described_class.send_message(template_name: :confirmation, to: "+32499999999", parameters: { code: "123" })
    end

    it 'lève TemplateNotSyncedError si le template n\'existe pas' do
      expect {
        described_class.send_message(template_name: :missing, to: "+32499999999")
      }.to raise_error(SentDmClient::TemplateNotSyncedError, /introuvable/)
    end

    it 'lève TemplateNotSyncedError si le template n\'a pas d\'external_id' do
      create(:sms_template, :unsynced, name: "unsynced_template")
      expect {
        described_class.send_message(template_name: :unsynced_template, to: "+32499999999")
      }.to raise_error(SentDmClient::TemplateNotSyncedError, /non synchronisé/)
    end
  end

  describe '.create_template' do
    it 'POST /v3/templates avec name et definition' do
      stub_request(:post, "https://api.sent.dm/v3/templates")
        .with(headers: { "x-api-key" => "test-key", "Content-Type" => "application/json" })
        .to_return(status: 201, body: { success: true, data: { id: "tmpl_abc" } }.to_json, headers: { "Content-Type" => "application/json" })

      response = described_class.create_template(
        name: "demo",
        category: "UTILITY",
        language: "fr",
        body: "Bonjour {{0:name}}",
        variables: [ { "id" => 0, "name" => "name", "sample" => "Lucas" } ]
      )

      expect(response.parsed_response.dig("data", "id")).to eq("tmpl_abc")
    end

    it 'lève APIError sur réponse non 2xx' do
      stub_request(:post, "https://api.sent.dm/v3/templates")
        .to_return(status: 422, body: '{"error":"bad"}')

      expect {
        described_class.create_template(name: "demo", category: "UTILITY", language: "fr", body: "x", variables: [])
      }.to raise_error(SentDmClient::APIError, /422/)
    end
  end

  describe 'configuration' do
    it 'lève ConfigurationError si SENT_DM_API_KEY manquant' do
      allow(ENV).to receive(:[]).with("SENT_DM_API_KEY").and_return(nil)
      described_class.reset!
      create(:sms_template, name: "x")

      expect {
        described_class.send_message(template_name: :x, to: "+32499999999")
      }.to raise_error(SentDmClient::ConfigurationError)
    end
  end
end
