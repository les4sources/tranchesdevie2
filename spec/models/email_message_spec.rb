require 'rails_helper'

RSpec.describe EmailMessage, type: :model do
  it 'is valid with the required attributes' do
    expect(build(:email_message)).to be_valid
  end

  it 'requires a recipient, sender and body' do
    message = EmailMessage.new
    message.valid?
    expect(message.errors[:to_email]).to be_present
    expect(message.errors[:from_email]).to be_present
    expect(message.errors[:body_html]).to be_present
  end

  # Les valeurs entières sont persistées : les renuméroter réécrirait le sens des
  # lignes déjà en base. Ce que ce garde-fou protège, c'est donc la STABILITÉ des
  # paires existantes — pas la liste des genres, qui s'allonge à chaque nouveau
  # courrier (les dix genres party sont arrivés avec #pizza-parties). Écrit en
  # `include` et non en `eq` pour cette raison : un ajout passe, un déplacement
  # échoue.
  it 'garde les valeurs entières existantes stables' do
    expect(EmailMessage.kinds).to include(
      "confirmation" => 0, "otp" => 1, "other" => 2, "ready" => 3, "party_team_notification" => 4,
      "party_request_received" => 5, "party_request_team" => 6, "party_request_accepted" => 7,
      "party_request_refused" => 8, "party_request_expired" => 9, "party_payment_prompt" => 10,
      "party_payment_reminder" => 11, "party_payment_expired" => 12, "party_cancelled" => 13,
      "party_refunded" => 14
    )
  end

  it 'belongs optionally to a customer and an order' do
    expect(build(:email_message, customer: nil, order: nil)).to be_valid
  end
end
