require 'rails_helper'

# Synchronisation de la ligne forfait Pizza party (#68).
RSpec.describe PizzaPartyForfaitService do
  # Produit « party » (1 boule / personne) — déclencheur du forfait.
  let!(:party_product) do
    create(:product, :dough_ball, channel: 'store', pizza_party_role: :party)
  end
  let!(:party_variant) do
    create(:product_variant, product: party_product, name: 'une boule', price_cents: 500, channel: 'store')
  end

  # Produit forfait (admin) avec sa variante store à 40 €.
  let!(:forfait_product) do
    create(:product, :dough_ball, :admin_channel, pizza_party_role: :forfait)
  end
  let!(:forfait_variant) do
    create(:product_variant, product: forfait_product, name: 'forfait', price_cents: 4000, channel: 'store')
  end

  # Produit ordinaire, sans lien pizza party.
  let!(:bread_product) { create(:product, channel: 'store', pizza_party_role: :none) }
  let!(:bread_variant) { create(:product_variant, product: bread_product, price_cents: 550, channel: 'store') }

  def line(variant, qty)
    {
      'product_variant_id' => variant.id.to_s,
      'qty' => qty,
      'name' => variant.name,
      'price_cents' => variant.price_cents
    }
  end

  def forfait_lines(cart)
    cart.select { |item| item['product_variant_id'] == forfait_variant.id.to_s }
  end

  describe '.sync' do
    it 'ajoute exactement une ligne forfait quand un produit party est présent' do
      cart = [ line(party_variant, 3) ]
      result = described_class.sync(cart)

      expect(forfait_lines(result).size).to eq(1)
      forfait = forfait_lines(result).first
      expect(forfait['qty']).to eq(1)
      expect(forfait['price_cents']).to eq(4000)
    end

    it 'ne crée pas de forfait quand aucun produit party n\'est présent' do
      cart = [ line(bread_variant, 2) ]
      result = described_class.sync(cart)

      expect(forfait_lines(result)).to be_empty
      expect(result).to eq(cart)
    end

    it 'retire un forfait orphelin quand le produit party a disparu du panier' do
      cart = [ line(bread_variant, 1), line(forfait_variant, 1) ]
      result = described_class.sync(cart)

      expect(forfait_lines(result)).to be_empty
    end

    it 'ne garde qu\'UN forfait même avec plusieurs produits party' do
      other_party = create(:product, :dough_ball, channel: 'store', pizza_party_role: :party)
      other_party_variant = create(:product_variant, product: other_party, price_cents: 500, channel: 'store')

      cart = [ line(party_variant, 2), line(other_party_variant, 4) ]
      result = described_class.sync(cart)

      expect(forfait_lines(result).size).to eq(1)
    end

    it 'dédoublonne un panier contenant déjà plusieurs lignes forfait' do
      cart = [ line(party_variant, 1), line(forfait_variant, 1), line(forfait_variant, 1) ]
      result = described_class.sync(cart)

      expect(forfait_lines(result).size).to eq(1)
    end

    it 'est idempotent (sync deux fois == sync une fois)' do
      cart = [ line(party_variant, 3), line(bread_variant, 1) ]
      once = described_class.sync(cart)
      twice = described_class.sync(once)

      expect(twice).to eq(once)
    end

    it 'ne mute pas le panier reçu' do
      cart = [ line(party_variant, 1) ]
      frozen_snapshot = cart.map(&:dup)
      described_class.sync(cart)

      expect(cart).to eq(frozen_snapshot)
    end

    it 'gère un panier vide ou nil sans crasher' do
      expect(described_class.sync([])).to eq([])
      expect(described_class.sync(nil)).to eq([])
    end

    context 'quand le produit forfait est absent de la base (pas de seeds)' do
      before do
        forfait_variant.destroy
        forfait_product.really_destroy! if forfait_product.respond_to?(:really_destroy!)
        forfait_product.destroy
      end

      it 'ne crashe pas et laisse le panier party intact' do
        cart = [ line(party_variant, 2) ]
        expect { described_class.sync(cart) }.not_to raise_error
        result = described_class.sync(cart)
        expect(result).to eq(cart)
      end
    end
  end
end
