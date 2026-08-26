require "rails_helper"

# #208 — le CRUD des ateliers dans l'admin.
RSpec.describe "Admin::Workshops", type: :request do
  before do
    ENV["ADMIN_PASSWORD"] = "test-admin-pw"
    post admin_login_path, params: { password: "test-admin-pw" }
  end

  let(:romane) { create(:artisan, name: "Romane") }
  let(:stephanie) { create(:artisan, name: "Stéphanie") }

  describe "GET index" do
    it "liste les ateliers, à venir et passés" do
      create(:workshop, title: "Atelier pain", held_on: Date.current + 7, revenue_cents: 30_000, artisans: [ romane ])
      create(:workshop, title: "Atelier pizza", held_on: Date.current - 20, revenue_cents: 20_000, artisans: [ stephanie ])

      get admin_workshops_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Atelier pain")
      expect(response.body).to include("Atelier pizza")
      expect(response.body).to include("Ateliers à venir")
      expect(response.body).to include("Ateliers passés")
      expect(response.body).to include("Romane")
    end

    it "annonce que la répartition n'est pas définie tant qu'aucun taux n'est saisi" do
      get admin_workshops_path

      expect(response.body).to include("Répartition non définie")
      expect(response.body).to include("ne sont réparties à personne")
    end

    it "annonce le taux dès qu'il est saisi" do
      create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1))

      get admin_workshops_path

      expect(response.body).to include("30.0 % aux 4 Sources")
      expect(response.body).not_to include("Répartition non définie")
    end

    it "signale un atelier sans animateur" do
      create(:workshop, title: "Atelier orphelin", held_on: Date.current + 3, artisans: [])

      get admin_workshops_path

      expect(response.body).to include("Non réparti — aucun animateur")
    end
  end

  describe "POST create" do
    it "crée l'atelier avec ses animateurs et sa recette en euros" do
      expect {
        post admin_workshops_path, params: {
          workshop: { held_on: Date.current + 7, title: "Atelier pain au levain",
                      description: "Deux heures de pratique.", notes: "12 tabliers",
                      revenue_euros: "300,00", artisan_ids: [ romane.id, stephanie.id ] }
        }
      }.to change(Workshop, :count).by(1)

      workshop = Workshop.last
      expect(response).to redirect_to(admin_workshops_path)
      expect(workshop.revenue_cents).to eq(30_000)
      expect(workshop.artisans).to contain_exactly(romane, stephanie)
      expect(workshop.notes).to eq("12 tabliers")
    end

    it "refuse un atelier sans intitulé" do
      post admin_workshops_path, params: { workshop: { held_on: Date.current, title: "", revenue_euros: "10" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Correction requise")
    end

    it "accepte un atelier sans animateur — il sera signalé comme non réparti" do
      expect {
        post admin_workshops_path, params: {
          workshop: { held_on: Date.current + 7, title: "À caler", revenue_euros: "150,00" }
        }
      }.to change(Workshop, :count).by(1)

      expect(Workshop.last).to be_unassigned
    end
  end

  describe "PATCH update" do
    it "modifie l'atelier et ses animateurs" do
      workshop = create(:workshop, title: "Atelier pain", revenue_cents: 30_000, artisans: [ romane ])

      patch admin_workshop_path(workshop), params: {
        workshop: { held_on: workshop.held_on, title: "Atelier pain — édition 2",
                    revenue_euros: "450,00", artisan_ids: [ stephanie.id ] }
      }

      workshop.reload
      expect(response).to redirect_to(admin_workshops_path)
      expect(workshop.title).to eq("Atelier pain — édition 2")
      expect(workshop.revenue_cents).to eq(45_000)
      expect(workshop.artisans).to contain_exactly(stephanie)
    end
  end

  describe "DELETE destroy" do
    it "supprime l'atelier" do
      workshop = create(:workshop, artisans: [ romane ])

      expect { delete admin_workshop_path(workshop) }.to change(Workshop, :count).by(-1)
      expect(response).to redirect_to(admin_workshops_path)
    end
  end

  describe "le rapport Revenus boulangers" do
    it "affiche une section Ateliers, séparée de la production" do
      create(:revenue_parameter, :workshop_rate, value: 3_000, active_from: Date.new(2026, 1, 1))
      create(:artisan_revenue_share, artisan: romane, percent: 100, active_from: Date.new(2026, 1, 1))
      create(:workshop, title: "Atelier pizza", held_on: Date.current - 3, revenue_cents: 20_000, artisans: [ romane ])

      get baker_revenue_admin_reports_path(start_date: Date.current - 30, end_date: Date.current)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ateliers (revenu complémentaire)")
      expect(response.body).to include("Atelier pizza")
      expect(response.body).to include("Total ateliers")
    end

    it "signale les ateliers non répartis dans le rapport" do
      create(:workshop, title: "Atelier sans taux", held_on: Date.current - 3, revenue_cents: 20_000, artisans: [ romane ])

      get baker_revenue_admin_reports_path(start_date: Date.current - 30, end_date: Date.current)

      expect(response.body).to include("ne sont répartis à personne")
      expect(response.body).to include("taux non défini")
    end
  end

  describe "la navigation" do
    it "expose l'onglet Ateliers" do
      get admin_workshops_path

      expect(response.body).to include("Ateliers")
      expect(response.body).to include(admin_workshops_path)
    end
  end
end
