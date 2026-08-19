# frozen_string_literal: true

# Primitives d'interface de l'admin.
#
# Le CSS vit dans `app/assets/tailwind/application.css` (couche `.adm-*`) ; ce
# module ne fait que choisir la bonne variante et rendre le balisage répétitif.
# Objectif : qu'une vue admin n'ait jamais à connaître une couleur.
module Admin::UiHelper
  # Correspondance statut de commande → tonalité de pastille. Une seule table,
  # pour que la même commande ait la même couleur partout dans l'admin.
  ORDER_STATUS_TONES = {
    "pending" => :warning,
    "planned" => :water,
    "unpaid" => :neutral,
    "paid" => :water,
    "ready" => :success,
    "picked_up" => :neutral,
    "no_show" => :danger,
    "cancelled" => :danger
  }.freeze

  PAYMENT_STATUS_TONES = {
    "unpaid" => :neutral,
    "paid" => :success,
    "partially_paid" => :warning,
    "refunded" => :accent
  }.freeze

  TONES = %i[neutral brand accent success warning danger water].freeze

  # Pastille d'état. `tone` est une tonalité sémantique, jamais une couleur.
  def adm_chip(label, tone: :neutral, icon: nil)
    tone = :neutral unless TONES.include?(tone.to_sym)
    content = icon ? safe_join([ lucide(icon, size: 11), label.to_s ]) : label.to_s

    tag.span(content, class: "adm-chip adm-chip-#{tone}")
  end

  def adm_order_status_chip(status)
    adm_chip(order_status_label(status), tone: ORDER_STATUS_TONES.fetch(status.to_s, :neutral))
  end

  def adm_payment_status_chip(payment_status)
    adm_chip(payment_status_label(payment_status), tone: PAYMENT_STATUS_TONES.fetch(payment_status.to_s, :neutral))
  end

  # Classes de bouton. `variant` ∈ primary | default | ghost | danger.
  def adm_btn_class(variant = :default, extra = nil)
    variant = :default unless %i[primary default ghost danger].include?(variant.to_sym)
    [ "adm-btn", "adm-btn-#{variant}", extra ].compact.join(" ")
  end

  def adm_field_class(extra = nil)
    [ "adm-field", extra ].compact.join(" ")
  end

  # En-tête de page : titre en Caveat (la voix de la maison) + actions à droite.
  def adm_page_header(title, &actions)
    tag.div(class: "mb-4 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between") do
      safe_join([
        tag.h1(title, class: "tdv-script text-3xl"),
        actions ? tag.div(capture(&actions), class: "flex flex-wrap items-center gap-2") : nil
      ].compact)
    end
  end

  # État vide d'une grille. `colspan` doit couvrir toute la largeur du tableau.
  def adm_empty_row(colspan:, title:, hint: nil, &action)
    tag.tr do
      tag.td(colspan: colspan, class: "px-4 py-16 text-center") do
        safe_join([
          tag.div(lucide("search", size: 20), class: "mx-auto mb-3 flex h-11 w-11 items-center justify-center rounded-full",
                                              style: "background: var(--surface-sunk); color: var(--text-faint);"),
          tag.p(title, class: "text-sm font-semibold", style: "color: var(--text-strong);"),
          hint ? tag.p(hint, class: "mt-1 text-sm", style: "color: var(--text-muted);") : nil,
          action ? tag.div(capture(&action), class: "mt-4") : nil
        ].compact)
      end
    end
  end
end
