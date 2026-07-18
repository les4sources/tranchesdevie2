require "rails_helper"

RSpec.describe RevenuePartnershipMembership, type: :model do
  it "empêche un artisan d'appartenir à deux partenariats" do
    artisan = create(:artisan)
    create(:revenue_partnership_membership, artisan: artisan)

    duplicate = build(:revenue_partnership_membership, artisan: artisan)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:artisan_id]).to include("appartient déjà à un partenariat")
  end

  it "refuse un poids négatif" do
    membership = build(:revenue_partnership_membership, weight: -1)
    expect(membership).not_to be_valid
  end

  it "accepte un artisan et un partenariat valides à poids égal" do
    expect(build(:revenue_partnership_membership, weight: 1)).to be_valid
  end
end
