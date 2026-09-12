module Admin
  module OrdersHelper
    # Fenêtre de régularisation (#198) : au-delà, un jour passé n'a plus de
    # raison d'apparaître dans le sélecteur — mais le jour DÉJÀ porté par la
    # commande y reste toujours, sinon l'éditer la déplacerait en silence.
    REGULARISATION_WINDOW = 90

    # Jours de cuisson proposables à l'admin, groupés : les jours à venir, et
    # les jours passés qu'on peut encore régulariser. Le groupement n'est pas
    # cosmétique — c'est ce qui dit au boulanger qu'il sort du cours normal.
    def admin_bake_day_options(order)
      future, past = admin_selectable_bake_days(order).partition { |day| day.baked_on >= Date.current }

      groups = []
      groups << [ "À venir", future.map { |day| bake_day_option(day) } ] if future.any?
      groups << [ "Jours passés — régularisation", past.reverse.map { |day| bake_day_option(day) } ] if past.any?
      groups
    end

    # Ids des jours passés présents dans le sélecteur, pour que l'avertissement
    # s'affiche dès le choix, sans attendre l'enregistrement.
    def admin_past_bake_day_ids(order)
      admin_selectable_bake_days(order).reject { |day| day.baked_on >= Date.current }.map(&:id)
    end

    # Compteur « encaissé X / Y » d'un point de retrait (#275). Recalculé à
    # chaque pointage : c'est ce qui donne au boulanger l'avancement de sa
    # remise sans quitter la page.
    #
    # Les commandes prises en compte sont celles que la page affiche déjà pour
    # ce lieu — mêmes statuts de production, même fournée.
    def pickup_settlement_counter(bake_day, pickup_location)
      orders = Order.where(bake_day: bake_day, pickup_location: pickup_location)
                    .where(status: Admin::BakeDayDashboard::PRODUCTION_STATUSES)
                    .includes(:payment, :wallet_transactions)

      settled = orders.reject(&:settlement_pending?)

      { settled_cents: settled.sum(&:total_cents), total_cents: orders.sum(&:total_cents) }
    end

    # Montant du jour dont l'encaissement n'est pas pointé (#275), recalculé
    # après chaque pointage pour que la bannière ne reste pas périmée à l'écran.
    def bake_day_settlement_pending_cents(bake_day)
      Order.where(bake_day: bake_day)
           .where(status: Admin::BakeDayDashboard::PRODUCTION_STATUSES)
           .includes(:payment, :wallet_transactions)
           .select(&:settlement_pending?)
           .sum(&:total_cents)
    end

    private

    def admin_selectable_bake_days(order)
      days = BakeDay.where("baked_on >= ?", Date.current - REGULARISATION_WINDOW).ordered.to_a
      current = order&.bake_day
      days << current if current && days.exclude?(current)
      days.sort_by(&:baked_on)
    end

    # `strftime` rendait « Tuesday 25/08/2026 » dans une interface entièrement
    # en français : `I18n.l` va chercher les noms de jours de la locale `fr`.
    def bake_day_option(day)
      label = I18n.l(day.baked_on, format: "%A %d/%m/%Y").capitalize
      label = "#{label} — brouillon" if day.respond_to?(:draft?) && day.draft?
      [ label, day.id ]
    end
  end
end
