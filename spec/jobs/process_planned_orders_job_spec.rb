require "rails_helper"

# Rythme et périmètre du traitement des commandes du calendrier (#274).
#
# Le cron passait dimanche et mercredi 18h05 alors que les cut-offs sont fixés
# PAR FOURNÉE (jeudi 16h pour le vendredi, lundi 16h pour le mardi) : le passage
# du mercredi était trop tôt, celui du dimanche arrivait après la fournée. Les
# commandes restaient `planned` le jour de la cuisson — donc hors de la feuille
# compta — et le client ne recevait jamais son SMS.
#
# Le job passe désormais tous les jours à 16h05 ; c'est ce scope qui le rend
# sans effet les jours sans cut-off.
RSpec.describe ProcessPlannedOrdersJob, type: :job do
  let(:customer) { create(:customer) }

  # ISC-56 : le job délègue chaque fournée éligible au service (déjà testé par
  # ailleurs). On vérifie ici sa logique de SÉLECTION.
  describe "délégation au service" do
    before { allow(SlackService).to receive(:send_message) }

    it "traite une fournée dont le cut-off est passé et qui a des commandes planifiées" do
      bake_day = create(:bake_day, :cut_off_passed)
      create(:order, :planned, bake_day: bake_day)
      expect(ProcessPlannedOrdersService).to receive(:process_for_bake_day).with(bake_day)
      described_class.perform_now
    end

    it "ignore une fournée dont le cut-off est passé mais sans commande planifiée" do
      create(:bake_day, :cut_off_passed)
      expect(ProcessPlannedOrdersService).not_to receive(:process_for_bake_day)
      described_class.perform_now
    end
  end

  def planned_order_on(bake_day)
    create(:order, :planned, customer: customer, bake_day: bake_day, total_cents: 1_200)
  end

  describe ".pending_bake_days" do
    it "retient une fournée dont le cut-off vient de passer" do
      bake_day = create(:bake_day, baked_on: Date.current + 1, cut_off_at: 3.hours.ago)
      planned_order_on(bake_day)

      expect(described_class.pending_bake_days).to include(bake_day)
    end

    it "ignore une fournée dont le cut-off n'est pas encore passé" do
      bake_day = create(:bake_day, baked_on: Date.current + 3, cut_off_at: 2.hours.from_now)
      planned_order_on(bake_day)

      expect(described_class.pending_bake_days).not_to include(bake_day)
    end

    it "ignore une fournée sans commande planifiée" do
      bake_day = create(:bake_day, baked_on: Date.current + 1, cut_off_at: 3.hours.ago)

      expect(described_class.pending_bake_days).not_to include(bake_day)
    end

    # C'est le symptôme qui a motivé #274 : avec un cron hebdomadaire désaligné,
    # des commandes restaient `planned` bien après leur cut-off.
    it "rattrape une fournée dont le cut-off est passé depuis plus de 24 heures" do
      stale = create(:bake_day, baked_on: Date.current - 1, cut_off_at: 3.days.ago)
      planned_order_on(stale)

      expect(described_class.pending_bake_days).to include(stale)
    end
  end

  describe "#perform" do
    it "ne laisse aucune commande planifiée sur une fournée dont le cut-off est passé" do
      bake_day = create(:bake_day, baked_on: Date.current + 1, cut_off_at: 3.hours.ago)
      order = planned_order_on(bake_day)
      create(:wallet, customer: customer, balance_cents: 10_000)
      allow(SmsService).to receive(:send_planned_order_confirmed)

      described_class.new.perform

      expect(order.reload.status).not_to eq("planned")
      expect(described_class.pending_bake_days).to be_empty
    end
  end
end
