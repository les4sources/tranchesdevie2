require "rails_helper"

# #204 — pizza party privée créée à la main. « Elle avait commandé par mail. »
#
# La démonstration centrale : une party créée à la main et payée produit
# exactement le même revenu qu'une party réservée en ligne — avec ET sans
# forfait. Elle passe par le même `PartyOrderCreationService`, donc l'égalité
# est structurelle.
RSpec.describe ManualPrivatePartyService do
  # Dates calculées depuis aujourd'hui, jamais figées : la réservation EN LIGNE
  # de référence passe par le service CLIENT, qui refuse un créneau dont le
  # cut-off est dépassé. Une date en dur finit toujours par tomber dans le
  # passé — et ce sont alors les specs de revenu qui cassent, un an plus tard,
  # sans qu'une ligne de code ait bougé.
  let(:date) { Date.current.next_occurring(:friday) + 1.week }        # un vendredi à venir
  let(:wednesday) { Date.current.next_occurring(:wednesday) + 1.week } # un mercredi : interdit au client

  let!(:default_pickup) { create(:pickup_location, :default) }
  let!(:bake_day) { create(:bake_day, baked_on: date, cut_off_at: date - 2.days) }

  let(:party_product) { create(:product, :pizza_party, name: "Pizza party privée") }
  let!(:paton) { create(:product_variant, product: party_product, name: "une boule", price_cents: 500, flour_quantity: 200, channel: "store") }
  let(:forfait_product) { create(:product, :pizza_party_forfait, name: "Forfait Pizza party privée") }
  let!(:forfait) { create(:product_variant, product: forfait_product, name: "forfait", price_cents: 4_000, channel: "store") }

  before do
    create(:revenue_parameter, :four_sources_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
    create(:variant_cost_price, product_variant: paton, amount_cents: 26, active_from: date - 30)
  end

  def build(persons: 8, held_on: date, slot: "soir", name: "Fabienne Renard", forfait: true, paid: true, **rest)
    described_class.new(held_on: held_on, slot: slot, persons: persons, name: name,
                        forfait: forfait, paid: paid, **rest)
  end

  describe "la création" do
    it "crée l'événement privé et sa commande, marquée ajoutée à la main" do
      service = build(persons: 8)
      event = service.call

      expect(event).to be_a(PartyEvent)
      expect(event.kind_private_party?).to be true
      expect(event.held_on).to eq(date)
      expect(event.slot).to eq("soir")

      order = service.order
      expect(order.manually_added?).to be true
      expect(order.source).to eq("party")
      expect(order.paid?).to be true
      expect(order.total_cents).to eq(8 * 500 + 4_000)
    end

    it "crée un client sans numéro de téléphone" do
      service = build(name: "Sans Téléphone", email: "party@example.test")
      service.call

      customer = service.order.customer
      expect(customer.phone_e164).to be_nil
      expect(customer.email).to eq("party@example.test")
      expect(customer.first_name).to eq("Sans")
    end

    it "réutilise un client existant désigné explicitement" do
      existing = create(:customer, first_name: "Romane", last_name: "Ancion")

      service = described_class.new(held_on: date, slot: "soir", persons: 4, customer_id: existing.id, paid: true)
      service.call

      expect(service.order.customer).to eq(existing)
    end

    it "omet la ligne forfait quand on ne le veut pas" do
      service = build(persons: 8, forfait: false)
      service.call

      expect(service.order.total_cents).to eq(8 * 500)
      expect(service.order.order_items.map { |i| i.product_variant.product.pizza_party_role })
        .to all(eq("party"))
    end

    it "refuse une saisie incomplète" do
      expect(build(persons: 0).call).to be false
      expect(described_class.new(held_on: date, slot: "", persons: 4, name: "X").call).to be false
      expect(described_class.new(held_on: date, slot: "soir", persons: 4).call).to be false
    end
  end

  # Les règles de réservation CLIENT (#201) ne s'appliquent pas à l'admin.
  describe "hors des règles de réservation client" do
    it "accepte un créneau que le client ne pourrait PAS réserver — ici bloqué par l'équipe" do
      PartySlotBlock.create!(blocked_on: wednesday, slot: "midi", reason: "Fermé au public")
      expect(PartyEvent.private_slot_available?(wednesday, "midi")).to be false

      service = build(held_on: wednesday, slot: "midi", persons: 6)
      event = service.call

      expect(event).to be_a(PartyEvent)
      expect(event.held_on).to eq(wednesday)
      expect(event.slot).to eq("midi")
    end

    it "accepte une date pour demain, hors de tout délai client" do
      tomorrow = Date.current + 1
      expect(PartyEvent.private_slot_available?(tomorrow, "soir")).to be false

      service = build(held_on: tomorrow, slot: "soir", persons: 6)

      expect(service.call).to be_a(PartyEvent)
    end

    it "accepte un créneau déjà plein pour le client" do
      PartyEvent.private_slot_capacity.times do
        create(:party_event, :private_party, held_on: wednesday, slot: "soir")
      end
      expect(PartyEvent.private_slot_available?(wednesday, "soir")).to be false

      expect(build(held_on: wednesday, slot: "soir", persons: 6).call).to be_a(PartyEvent)
    end
  end

  # ---- Le cœur de l'issue : l'équivalence de revenu ----
  describe "revenus" do
    # Une réservation EN LIGNE de référence, par le service client.
    def online(persons:, with_forfait: true)
      customer = create(:customer)
      items = [ { "product_variant_id" => paton.id.to_s, "qty" => persons.to_s } ]
      items << { "product_variant_id" => forfait.id.to_s, "qty" => "1" } if with_forfait

      service = PartyReservationService.new(
        customer: customer, date: date.iso8601, slot: "soir",
        cart_items: items, payment_method: "cash", customer_note: "On arrive vers 18h30."
      )
      service.call
      service.order.tap { |order| order.update!(status: :paid) }
    end

    it "avec forfait : mêmes chiffres qu'une réservation en ligne" do
      manual = build(persons: 8, forfait: true).tap(&:call)
      web = online(persons: 8, with_forfait: true)

      manual_result = PizzaPartyRevenueService.call([ manual.order ])
      web_result = PizzaPartyRevenueService.call([ web ])

      expect(manual_result.persons).to eq(web_result.persons)
      expect(manual_result.sale_cents).to eq(web_result.sale_cents)
      expect(manual_result.four_sources_cents).to eq(web_result.four_sources_cents)
      expect(manual_result.bakers_cents).to eq(web_result.bakers_cents)
    end

    it "sans forfait : mêmes chiffres qu'une réservation en ligne sans forfait" do
      manual = build(persons: 8, forfait: false).tap(&:call)
      web = online(persons: 8, with_forfait: false)

      manual_result = PizzaPartyRevenueService.call([ manual.order ])
      web_result = PizzaPartyRevenueService.call([ web ])

      expect(manual_result.sale_cents).to eq(web_result.sale_cents)
      expect(manual_result.four_sources_cents).to eq(web_result.four_sources_cents)
      expect(manual_result.bakers_cents).to eq(web_result.bakers_cents)
      # Et le forfait n'est effectivement pas compté.
      with_forfait = PizzaPartyRevenueService.call([ build(persons: 8, forfait: true).tap(&:call).order ])
      expect(with_forfait.bakers_cents - manual_result.bakers_cents).to eq(3_000)
      expect(with_forfait.four_sources_cents - manual_result.four_sources_cents).to eq(1_000)
    end

    it "une party NON payée ne rapporte rien" do
      service = build(persons: 8, paid: false)
      service.call

      expect(service.order.status).to eq("unpaid")
      expect(Order.completed).not_to include(service.order)
      expect(PizzaPartyRevenueService.call(Order.completed.where(id: service.order.id)).sale_cents).to eq(0)
    end

    it "bascule non payée → payée et se met à comptabiliser" do
      service = build(persons: 8, paid: false)
      service.call

      described_class.toggle_paid(service.order, paid: true)

      expect(service.order.reload.paid?).to be true
      expect(PizzaPartyRevenueService.call(Order.completed.where(id: service.order.id)).persons).to eq(8)
    end
  end

  describe "sur le jour de cuisson" do
    it "apparaît avec le bon nombre de pâtons à préparer" do
      build(persons: 8, held_on: date, slot: "soir").call

      entry = Admin::BakeDayDashboard.new(bake_day).parties_to_prepare.first

      expect(entry).to be_present
      expect(entry[:paton_count]).to eq(8)
      expect(entry[:slot_label]).to eq("Soir")
    end
  end

  describe "la modification" do
    it "change la date, le créneau et les effectifs" do
      service = build(persons: 8)
      event = service.call

      described_class.new(party_event: event, held_on: wednesday, slot: "midi", persons: 4,
                          customer_id: service.order.customer_id, forfait: false, paid: true).call

      expect(event.reload.held_on).to eq(wednesday)
      expect(event.slot).to eq("midi")
      expect(service.order.reload.total_cents).to eq(4 * 500)
    end
  end
end
