require "rails_helper"

# Défaut de calcul du cut-off : la veille de la cuisson à 12h00 (#292).
RSpec.describe BakeDay, ".calculate_cut_off_for" do
  it "place le cut-off d'un mardi le lundi à 12h00" do
    cut_off = described_class.calculate_cut_off_for(Date.new(2026, 9, 22))

    expect(cut_off).to eq(Time.zone.parse("2026-09-21 12:00:00"))
    expect(cut_off.strftime("%A")).to eq("Monday")
  end

  it "place le cut-off d'un vendredi le jeudi à 12h00" do
    cut_off = described_class.calculate_cut_off_for(Date.new(2026, 9, 25))

    expect(cut_off).to eq(Time.zone.parse("2026-09-24 12:00:00"))
    expect(cut_off.strftime("%A")).to eq("Thursday")
  end

  it "ne calcule rien pour un jour qui n'est pas un jour de cuisson" do
    expect(described_class.calculate_cut_off_for(Date.new(2026, 9, 23))).to be_nil
  end

  # Le cut-off est un timestamptz : midi doit rester midi à Bruxelles des deux
  # côtés du changement d'heure, jamais 11h ou 13h.
  it "reste à midi heure de Bruxelles en heure d'été (UTC+2)" do
    cut_off = described_class.calculate_cut_off_for(Date.new(2026, 7, 7))

    expect(cut_off.in_time_zone("Europe/Brussels").hour).to eq(12)
    expect(cut_off.utc_offset).to eq(2 * 3600)
  end

  it "reste à midi heure de Bruxelles en heure d'hiver (UTC+1)" do
    cut_off = described_class.calculate_cut_off_for(Date.new(2027, 1, 12))

    expect(cut_off.in_time_zone("Europe/Brussels").hour).to eq(12)
    expect(cut_off.utc_offset).to eq(1 * 3600)
  end

  it "ne réserve qu'un seul jour de battement avant la cuisson" do
    expect(BakeDay::COOKING_DAYS.values.uniq).to eq([ 1 ])
  end
end
