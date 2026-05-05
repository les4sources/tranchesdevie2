require 'rails_helper'

RSpec.describe SmsTemplatesSeeder do
  let(:create_response) { double("HTTParty::Response", parsed_response: { "data" => { "id" => "tmpl_remote" } }) }
  let(:draft_status) { double("APIResponse", data: double(status: "DRAFT")) }
  let(:pending_status) { double("APIResponse", data: double(status: "PENDING")) }

  before do
    allow(SentDmClient).to receive(:create_template).and_return(create_response)
    allow(SentDmClient).to receive(:update_template).and_return(double)
    allow(SentDmClient).to receive(:retrieve_template).and_return(draft_status)
  end

  describe '.call' do
    it 'crée chaque template défini dans la config' do
      expect(SentDmClient).to receive(:create_template).at_least(:once).and_return(create_response)
      described_class.call

      expect(SmsTemplate.count).to eq(YAML.load_file(SmsTemplatesSeeder::CONFIG_PATH).fetch("templates").size)
      expect(SmsTemplate.all).to all(be_synced)
    end

    it 'est idempotent : un second appel met à jour sans dupliquer (templates en DRAFT)' do
      described_class.call
      initial_count = SmsTemplate.count

      expect(SentDmClient).not_to receive(:create_template)
      expect(SentDmClient).to receive(:update_template).at_least(:once)

      described_class.call

      expect(SmsTemplate.count).to eq(initial_count)
    end

    it 'skippe les templates en PENDING/APPROVED côté Sent.dm' do
      described_class.call

      allow(SentDmClient).to receive(:retrieve_template).and_return(pending_status)
      expect(SentDmClient).not_to receive(:update_template)
      expect(SentDmClient).not_to receive(:create_template)

      described_class.call
    end

    it 'persiste l\'external_id retourné par Sent.dm' do
      described_class.call
      expect(SmsTemplate.first.external_id).to eq("tmpl_remote")
    end
  end
end
