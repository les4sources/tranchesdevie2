require "rails_helper"

# Village déclaré par le client (retour Michael 19/10/2026) : la saisie est
# normalisée pour que le reporting ne compte pas « godinne » et « Godinne »
# comme deux villages.
RSpec.describe Customer, "locality" do
  def normalized(value)
    customer = build(:customer, locality: value)
    customer.valid?
    customer.locality
  end

  it "met une majuscule à chaque mot d'une saisie tout en minuscules ou en capitales" do
    expect(normalized("  mont-godinne ")).to eq("Mont-Godinne")
    expect(normalized("ANHÉE")).to eq("Anhée")
  end

  it "laisse une casse mixte telle quelle" do
    expect(normalized("Mont-sur-Meuse")).to eq("Mont-sur-Meuse")
  end

  it "ramène une saisie vide à nil" do
    expect(normalized("   ")).to be_nil
  end

  it "ne redemande plus le village à qui l'a donné ou a préféré ne pas répondre" do
    expect(build(:customer, locality: nil).locality_prompt?).to be(true)
    expect(build(:customer, locality: "Yvoir").locality_prompt?).to be(false)
    expect(build(:customer, locality: nil, locality_prompt_dismissed_at: Time.current).locality_prompt?).to be(false)
  end

  it "propose la liste de base et les villages déjà saisis, sans doublon de casse" do
    create(:customer, locality: "Sorinnes")
    create(:customer, locality: "Godinne")

    suggestions = Customer.locality_suggestions
    expect(suggestions).to include("Sorinnes", "Godinne", "Yvoir")
    expect(suggestions.count { |name| name.casecmp?("godinne") }).to eq(1)
  end
end
