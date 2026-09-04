require "rails_helper"

# « Quand venir chercher sa commande » (#252) : texte libre, facultatif, distinct
# de `description`. Aucune validation — les boulangers écrivent ce qu'ils veulent,
# ou rien.
RSpec.describe PickupLocation, "#pickup_instructions", type: :model do
  it "naît nil : la migration ne pré-remplit rien" do
    location = create(:pickup_location)

    expect(location.pickup_instructions).to be_nil
  end

  it "accepte nil sans invalider l'enregistrement" do
    location = create(:pickup_location, pickup_instructions: nil)

    expect(location).to be_valid
  end

  it "accepte une chaîne longue et multiligne" do
    texte = "Le jour de la cuisson, à partir de 18h.\n" + ("Détail supplémentaire. " * 100)
    location = create(:pickup_location, pickup_instructions: texte)

    expect(location.reload.pickup_instructions).to eq(texte)
  end

  it "reste distinct de la description" do
    location = create(
      :pickup_location,
      description: "Retrait sur notre étal, les jours de marché à Anhée.",
      pickup_instructions: "Le samedi, de 9h à 13h."
    )

    expect(location.description).to eq("Retrait sur notre étal, les jours de marché à Anhée.")
    expect(location.pickup_instructions).to eq("Le samedi, de 9h à 13h.")
  end
end
