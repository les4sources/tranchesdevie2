require 'rails_helper'

# Pose / retrait du post-it « Pizza party » sur le calendrier de claudy (#259).
RSpec.describe SyncClaudyPartyNoteJob do
  let!(:default_pickup) { create(:pickup_location, :default) }
  let(:api_url) { 'https://claudy.test' }
  let(:notes_url) { "#{api_url}/api/v1/notes" }

  let(:customer) { create(:customer, first_name: 'Michael', last_name: 'Hulet') }
  let(:party_product) { create(:product, :pizza_party, channel: 'store') }
  let(:party_variant) { create(:product_variant, product: party_product, price_cents: 500, channel: 'store') }

  around do |example|
    original_url = ENV['CLAUDY_API_URL']
    original_token = ENV['CLAUDY_API_TOKEN']
    ENV['CLAUDY_API_URL'] = api_url
    ENV['CLAUDY_API_TOKEN'] = 'tok_claudy'
    example.run
    ENV['CLAUDY_API_URL'] = original_url
    ENV['CLAUDY_API_TOKEN'] = original_token
  end

  def party_order(patons: 18, kind: :private_party, claudy_note_id: nil)
    event = create(:party_event, kind == :private_party ? :private_party : :public_party)
    order = create(:order, customer: customer, bake_day: nil, party_event: event, source: :party,
                           claudy_note_id: claudy_note_id)
    create(:order_item, order: order, product_variant: party_variant, qty: patons, unit_price_cents: 500)
    order.reload
  end

  describe 'création' do
    it "renseigne claudy_note_id avec l'identifiant renvoyé par claudy" do
      order = party_order
      stub_request(:post, notes_url).to_return(status: 201, body: { id: 501 }.to_json, headers: { 'Content-Type' => 'application/json' })

      described_class.perform_now(order.id, 'create')

      expect(order.reload.claudy_note_id).to eq(501)
    end

    it "n'émet aucune requête si la commande porte déjà une note" do
      order = party_order(claudy_note_id: 123)

      described_class.perform_now(order.id, 'create')

      expect(a_request(:post, notes_url)).not_to have_been_made
      expect(order.reload.claudy_note_id).to eq(123)
    end

    it "n'émet aucune requête pour une party PUBLIQUE" do
      order = party_order(kind: :public_party)

      described_class.perform_now(order.id, 'create')

      expect(a_request(:post, notes_url)).not_to have_been_made
    end

    it "n'émet aucune requête pour une commande de fournée ordinaire" do
      order = create(:order, customer: customer)

      described_class.perform_now(order.id, 'create')

      expect(a_request(:post, notes_url)).not_to have_been_made
    end

    # Un incident côté claudy ne doit jamais passer inaperçu : Sentry le voit, et
    # `retry_on` replanifie le job plutôt que d'abandonner la note en silence.
    it "signale l'erreur à Sentry et replanifie le job" do
      order = party_order
      stub_request(:post, notes_url).to_return(status: 500, body: 'boom')
      expect(Sentry).to receive(:capture_exception).with(instance_of(ClaudyClient::Error))

      original_adapter = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      begin
        expect { described_class.perform_now(order.id, 'create') }
          .to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }.by(1)
      ensure
        ActiveJob::Base.queue_adapter = original_adapter
      end

      expect(order.reload.claudy_note_id).to be_nil
    end

    it "laisse l'erreur remonter hors de #perform, pour que retry_on s'en saisisse" do
      order = party_order
      stub_request(:post, notes_url).to_return(status: 500, body: 'boom')
      allow(Sentry).to receive(:capture_exception)

      expect { described_class.new.perform(order.id, 'create') }.to raise_error(ClaudyClient::Error, /500/)
    end
  end

  describe 'suppression' do
    it "appelle DELETE et remet claudy_note_id à nil" do
      order = party_order(claudy_note_id: 501)
      stub = stub_request(:delete, "#{notes_url}/501").to_return(status: 204)

      described_class.perform_now(order.id, 'delete')

      expect(stub).to have_been_requested
      expect(order.reload.claudy_note_id).to be_nil
    end

    it "n'émet aucune requête si aucune note n'avait été posée" do
      order = party_order(claudy_note_id: nil)

      described_class.perform_now(order.id, 'delete')

      expect(a_request(:delete, %r{#{notes_url}/\d+})).not_to have_been_made
    end

    it "considère un 404 comme un succès et libère quand même claudy_note_id" do
      order = party_order(claudy_note_id: 501)
      stub_request(:delete, "#{notes_url}/501").to_return(status: 404)

      described_class.perform_now(order.id, 'delete')

      expect(order.reload.claudy_note_id).to be_nil
    end
  end

  it "ignore une commande disparue" do
    expect { described_class.perform_now(-1, 'create') }.not_to raise_error
  end
end
