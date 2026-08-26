require "rails_helper"

# #206 — import de la liste nominative des participants d'une party historique.
#
# Le dépôt est PUBLIC : tout ce qui suit est inventé (Faker), aucun participant
# réel n'apparaît ici. Le fichier de production est fourni à l'exécution et
# n'est jamais versionné.
#
# L'invariant qui compte : l'import ne crée AUCUNE commande et ne change AUCUN
# revenu. La comptabilité de ces événements vient de l'agrégat `historical_*`.
RSpec.describe PartyParticipantImporter do
  let(:date) { Date.new(2026, 7, 17) }
  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let!(:event) do
    create(:party_event, :public_party, held_on: date,
                                        historical_source: "billetweb",
                                        historical_adults: 35, historical_children: 16,
                                        historical_sourciers: 13, historical_fees_cents: 2_713)
  end

  let(:public_product) { create(:product, :pizza_party_public, name: "Pizza party publique") }
  let!(:adulte) { create(:product_variant, product: public_product, name: "adulte", price_cents: 1_000, party_four_sources_base_cents: 300) }
  let!(:enfant) { create(:product_variant, product: public_product, name: "enfant", price_cents: 600, party_four_sources_base_cents: 200) }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: adulte, amount_cents: 26, active_from: date - 30)
    create(:variant_cost_price, product_variant: enfant, amount_cents: 26, active_from: date - 30)
  end

  # Un CSV au format de l'export BilletWeb, avec des noms INVENTÉS.
  def write_csv(rows, with_bom: true)
    path = Rails.root.join("tmp", "participants-#{SecureRandom.hex(4)}.csv")
    header = %w[Tarif Nom Prénom Email Commande Prix Payé]

    body = ([ header ] + rows).map { |row| row.map { |value| %("#{value}") }.join(";") }.join("\n")
    File.write(path, "#{with_bom ? "﻿" : ''}#{body}\n")
    path
  end

  let(:invented_rows) do
    [
      [ "Place adulte", "Dupuis", "Camille", "camille.dupuis@example.test", "CMD001", "10,00", "Oui" ],
      [ "Place adulte", "Dupuis", "Alex", "camille.dupuis@example.test", "CMD001", "10,00", "Oui" ],
      [ "Place enfant", "Dupuis", "Lou", "camille.dupuis@example.test", "CMD001", "6,00", "Oui" ],
      [ "Place adulte", "Lemoine", "Sacha", "sacha.lemoine@example.test", "CMD002", "10,00", "Oui" ],
      # Les garnitures ne sont pas des places : décision du 20/07/2026.
      [ "Garnitures viande", "Dupuis", "Camille", "camille.dupuis@example.test", "CMD001", "3,00", "Oui" ],
      [ "Garnitures végé", "Lemoine", "Sacha", "sacha.lemoine@example.test", "CMD002", "3,00", "Oui" ]
    ]
  end

  def import(path)
    importer = described_class.new(party_event: event, path: path)
    [ importer.call, importer ]
  end

  describe "le format d'export" do
    it "lit un CSV « ; », guillemets et BOM UTF-8" do
      result, = import(write_csv(invented_rows))

      expect(result.created).to eq(4)
      expect(result.adults).to eq(3)
      expect(result.children).to eq(1)
    end

    it "trouve la première colonne malgré le BOM" do
      result, = import(write_csv(invented_rows, with_bom: true))

      expect(result.created).to eq(4)
      expect(PartyParticipant.pluck(:ticket_kind).uniq).to match_array(%w[adult child])
    end

    it "signale un fichier introuvable plutôt que de planter" do
      result, importer = import(Rails.root.join("tmp/n-existe-pas.csv"))

      expect(result).to be_nil
      expect(importer.errors.join).to include("introuvable")
    end
  end

  describe "les lignes qui ne sont pas des places" do
    it "les ignore et les compte" do
      result, = import(write_csv(invented_rows))

      expect(result.skipped_non_place).to eq(2)
      expect(PartyParticipant.pluck(:external_ticket_label)).not_to include("Garnitures viande", "Garnitures végé")
    end
  end

  describe "le regroupement par commande" do
    it "garde la référence de commande, qui regroupe les participants" do
      import(write_csv(invented_rows))

      grouped = PartyParticipant.where(party_event: event).group_by(&:external_reference)

      expect(grouped["CMD001"].size).to eq(3)
      expect(grouped["CMD002"].size).to eq(1)
    end
  end

  describe "l'idempotence" do
    it "relancé deux fois, ne duplique rien" do
      path = write_csv(invented_rows)

      first, = import(path)
      second, = import(path)

      expect(first.created).to eq(4)
      expect(second.created).to eq(0)
      expect(second.already_present).to eq(4)
      expect(PartyParticipant.where(party_event: event).count).to eq(4)
    end
  end

  # ---- L'invariant central ----
  describe "aucun impact comptable" do
    def revenue_snapshot
      {
        historical: HistoricalPartyRevenueService.call(event.reload),
        baker: BakerRevenueService.new(start_date: date, end_date: date).call
      }
    end

    it "ne crée AUCUNE commande" do
      expect { import(write_csv(invented_rows)) }.not_to change(Order, :count)
      expect(event.reload.orders).to be_empty
    end

    it "laisse les revenus strictement identiques, avant et après" do
      before_import = revenue_snapshot

      import(write_csv(invented_rows))

      after_import = revenue_snapshot

      expect(after_import[:historical].bakers_cents).to eq(before_import[:historical].bakers_cents)
      expect(after_import[:historical].four_sources_cents).to eq(before_import[:historical].four_sources_cents)
      expect(after_import[:historical].persons).to eq(before_import[:historical].persons)

      expect(after_import[:baker].total_revenue_cents).to eq(before_import[:baker].total_revenue_cents)
      expect(after_import[:baker].baker_pool_cents).to eq(before_import[:baker].baker_pool_cents)
      expect(after_import[:baker].four_sources_cents).to eq(before_import[:baker].four_sources_cents)
    end

    it "ne touche pas aux chiffres agrégés de l'événement" do
      import(write_csv(invented_rows))
      event.reload

      expect(event.historical_adults).to eq(35)
      expect(event.historical_children).to eq(16)
      expect(event.historical_sourciers).to eq(13)
      expect(event.historical_fees_cents).to eq(2_713)
    end
  end

  describe "le récapitulatif" do
    it "annonce créés, adultes, enfants et lignes ignorées" do
      result, = import(write_csv(invented_rows))

      expect(result.summary).to include("4 participants créés")
      expect(result.summary).to include("3 adultes")
      expect(result.summary).to include("1 enfant")
      expect(result.summary).to include("2 lignes ignorées")
    end
  end
end
