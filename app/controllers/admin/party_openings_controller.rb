module Admin
  # Ouvertures exceptionnelles des parties PRIVÉES (#pizza-parties).
  #
  # Miroir des blocages : ici on OUVRE un soir que la règle mardi/vendredi
  # ignore. Retirer une ouverture n'annule RIEN — les parties déjà réservées ce
  # soir-là restent entières, elles sont comptées à l'écran pour que le boulanger
  # voie ce qu'il laisse derrière lui.
  class PartyOpeningsController < Admin::BaseController
    def index
      @openings = upcoming_openings
      @opening = PartyOpening.new
      @booked = booked_counts(@openings)
    end

    def create
      @opening = PartyOpening.new(opening_params)

      unless @opening.save
        @openings = upcoming_openings
        @booked = booked_counts(@openings)
        return render :index, status: :unprocessable_entity
      end

      redirect_to admin_party_openings_path, notice: opening_notice(@opening)
    end

    def destroy
      PartyOpening.find(params[:id]).destroy

      redirect_to admin_party_openings_path,
        notice: "Date retirée. Les parties déjà réservées ce soir-là ne sont pas annulées."
    end

    private

    def upcoming_openings
      PartyOpening.upcoming
    end

    # Parties privées déjà posées sur les dates listées, en une requête.
    def booked_counts(openings)
      PartyEvent.private_events.not_deleted
                .where(held_on: openings.map(&:opened_on))
                .group(:held_on).count
    end

    def opening_notice(opening)
      return "Date ouverte — mais c'est déjà un jour de boulangerie, elle l'était donc déjà." if opening.redundant?

      "Date ouverte aux parties privées."
    end

    def opening_params
      params.require(:party_opening).permit(:opened_on, :reason)
    end
  end
end
