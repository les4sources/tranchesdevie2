module Admin::NavigationHelper
  # Les neuf destinations de l'admin, dans l'ordre où on s'en sert. Une seule
  # liste sert la barre latérale (desktop) et le tiroir (mobile) : impossible
  # qu'elles divergent.
  #
  # Avant la refonte, quatre d'entre elles n'étaient qu'une icône muette en
  # haut de page (€, graphique, engrenage, ?). Elles ont désormais leur nom.
  ADMIN_NAV = [
    { key: "orders",       label: "Commandes",         icon: "shopping-basket", path: :admin_orders_path },
    { key: "bake_days",    label: "Jours de cuisson",  icon: "flame",           path: :admin_bake_days_path },
    { key: "customers",    label: "Mangeurs",          icon: "users",           path: :admin_customers_path },
    { key: "products",     label: "Produits",          icon: "wheat",           path: :admin_products_path },
    { key: "party_events", label: "Parties",           icon: "party-popper",    path: :admin_party_events_path },
    { key: "workshops",    label: "Ateliers",          icon: "sprout",          path: :admin_workshops_path },
    { key: "billing",      label: "Facturation",       icon: "badge-euro",      path: :admin_billing_path },
    { key: "reports",      label: "Revenus boulangers", icon: "euro",           path: :baker_revenue_admin_reports_path },
    { key: "reports",      label: "Reporting",         icon: "chart-column",    path: :admin_reports_path },
    { key: "settings",     label: "Paramètres",        icon: "settings",        path: :admin_settings_path },
    { key: "help",         label: "Aide",              icon: "circle-help",     path: :admin_help_path }
  ].freeze

  def admin_nav_items
    ADMIN_NAV.map do |item|
      item.merge(href: public_send(item[:path]), active: admin_nav_active?(item[:key], item[:path]))
    end
  end

  def admin_nav_link_class(controller_name)
    admin_nav_active?(controller_name) ? "adm-navlink adm-navlink-active" : "adm-navlink"
  end

  def admin_mobile_nav_link_class(controller_name)
    base = "flex items-center gap-3 rounded-lg px-4 py-3 text-base font-medium"
    if admin_nav_active?(controller_name)
      "#{base} adm-navlink-active"
    else
      "#{base} adm-navlink"
    end
  end

  private

  # Deux entrées partagent le contrôleur `reports` (Revenus boulangers et
  # Reporting) : on les départage sur le chemin exact, sinon les deux
  # s'allumeraient ensemble.
  def admin_nav_active?(controller_name, path_helper = nil)
    return false unless base_nav_active?(controller_name)
    return true unless controller_name == "reports" && path_helper

    current_path = request.path
    if path_helper == :baker_revenue_admin_reports_path
      current_path.start_with?(baker_revenue_admin_reports_path)
    else
      !current_path.start_with?(baker_revenue_admin_reports_path)
    end
  end

  def base_nav_active?(controller_name)
    if controller_name == "orders"
      controller.controller_name == "orders" ||
        (controller.controller_path == "admin/sessions" && controller.action_name == "index")
    elsif controller_name == "settings"
      controller.controller_path == "admin/settings" || controller.controller_path.start_with?("admin/settings/")
    else
      controller.controller_name == controller_name
    end
  end
end
