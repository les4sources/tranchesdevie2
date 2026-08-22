# frozen_string_literal: true

module Admin
  module Settings
    module RevenuePartnershipsHelper
      # Artisans sélectionnables comme membres d'un partenariat : les artisans
      # actifs qui ne sont membres d'AUCUN autre partenariat. Les membres actuels
      # du partenariat en cours d'édition restent proposés (donc cochables).
      # Cela évite qu'un artisan soit affecté à deux partenariats (contrainte
      # d'unicité côté modèle).
      def eligible_artisans(partnership)
        Artisan
          .active
          .order(:name)
          .includes(:revenue_partnership_membership)
          .select do |artisan|
            membership = artisan.revenue_partnership_membership
            membership.nil? || membership.revenue_partnership_id == partnership.id
          end
      end
    end
  end
end
