require "rails_helper"
require "rake"

# #206 — la tâche rake d'import. Elle prend un CHEMIN en argument : le fichier
# réel contient des données personnelles et n'est jamais versionné.
RSpec.describe "party_participants:import" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("tasks/party_participants", [ Rails.root.join("lib").to_s ])
    Rake::Task.define_task(:environment)
  end

  before { Rake::Task["party_participants:import"].reenable }

  let(:date) { Date.new(2026, 7, 17) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:event) do
    create(:party_event, :public_party, held_on: date, historical_source: "billetweb",
                                        historical_adults: 35, historical_children: 16,
                                        historical_sourciers: 13, historical_fees_cents: 2_713)
  end

  # Données INVENTÉES.
  let(:path) do
    file = Rails.root.join("tmp", "rake-participants-#{SecureRandom.hex(4)}.csv")
    rows = [
      %w[Tarif Nom Prénom Email Commande Prix Payé],
      [ "Place adulte", "Dupuis", "Camille", "camille@example.test", "CMD001", "10,00", "Oui" ],
      [ "Place enfant", "Dupuis", "Lou", "camille@example.test", "CMD001", "6,00", "Oui" ],
      [ "Garnitures viande", "Dupuis", "Camille", "camille@example.test", "CMD001", "3,00", "Oui" ]
    ]
    File.write(file, "﻿#{rows.map { |r| r.map { |v| %("#{v}") }.join(';') }.join("\n")}\n")
    file
  end

  def run_task
    ENV["EVENT_ID"] = event.id.to_s
    ENV["FILE"] = path.to_s
    output = capture_stdout { Rake::Task["party_participants:import"].invoke }
    ENV.delete("EVENT_ID")
    ENV.delete("FILE")
    output
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it "importe les places, ignore les garnitures et affiche le récapitulatif" do
    output = run_task

    expect(PartyParticipant.where(party_event: event).count).to eq(2)
    expect(output).to include("2 participants créés")
    expect(output).to include("1 ligne ignorée")
    expect(output).to include("aucune commande n'a été créée")
  end

  it "ne crée aucune commande" do
    expect { run_task }.not_to change(Order, :count)
  end
end
