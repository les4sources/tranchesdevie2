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

  # Nature d'un message (SMS ou e-mail). Les deux modèles partagent le même
  # vocabulaire de `kind` : une seule table, pour qu'une confirmation ait la
  # même couleur qu'elle soit partie par SMS ou par e-mail.
  MESSAGE_KIND_TONES = {
    "confirmation" => :water,
    "ready" => :success,
    "refund" => :danger,
    "otp" => :accent,
    "other" => :neutral
  }.freeze

  MESSAGE_KIND_LABELS = {
    "confirmation" => "Confirmation",
    "ready" => "Prêt",
    "refund" => "Remboursement",
    "otp" => "OTP",
    "other" => "Autre"
  }.freeze

  WALLET_TRANSACTION_TONES = {
    "top_up" => :success,
    "order_debit" => :warning,
    "order_refund" => :water
  }.freeze

  WALLET_TRANSACTION_LABELS = {
    "top_up" => "Recharge",
    "order_debit" => "Débit commande",
    "order_refund" => "Remboursement"
  }.freeze

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

  # Pastille de nature d'un message, commune aux SMS et aux e-mails.
  def adm_message_kind_chip(kind)
    key = kind.to_s
    adm_chip(MESSAGE_KIND_LABELS.fetch(key, "Autre"), tone: MESSAGE_KIND_TONES.fetch(key, :neutral))
  end

  # Pastille de sens d'un message : sortant (parti de la boulangerie) ou entrant.
  def adm_message_direction_chip(outbound)
    adm_chip(outbound ? "Sortant" : "Entrant", tone: outbound ? :water : :success)
  end

  def adm_wallet_transaction_chip(transaction_type)
    key = transaction_type.to_s
    adm_chip(WALLET_TRANSACTION_LABELS.fetch(key, key), tone: WALLET_TRANSACTION_TONES.fetch(key, :neutral))
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

  # Nombre de teintes de drapeau définies dans la couche `.adm-flag-*`.
  FLAG_TONE_COUNT = 8

  # Une occupation → une tonalité. Les seuils (80 %, 100 %) vivent ici et non
  # dans chaque vue, pour qu'une fournée « presque pleine » ait la même couleur
  # sur la liste des jours et sur le tableau de bord.
  def adm_usage_tone(percentage)
    if percentage >= 100 then :danger
    elsif percentage >= 80 then :warning
    else :success
    end
  end

  # Jauge d'occupation. `percentage` peut dépasser 100 : la barre est bornée à
  # 100 % de largeur, mais la tonalité, elle, signale bien le dépassement.
  def adm_meter(percentage, tone: nil)
    tone ||= adm_usage_tone(percentage)

    tag.span(class: "adm-meter") do
      tag.span(class: "adm-meter-bar adm-tone-#{tone}", style: "width: #{[ percentage, 100 ].min}%")
    end
  end

  # Pastille ronde — le statut réduit à un point, là où le texte ne rentre pas.
  def adm_dot(tone: :neutral)
    tone = :neutral unless TONES.include?(tone.to_sym)

    tag.span(class: "adm-dot adm-tone-#{tone}")
  end

  # Teinte d'une carte « drapeau ». Purement distinctive : elle ne dit rien de
  # l'état du client, elle évite seulement que deux cartes voisines se
  # confondent. Au-delà de huit clients, les teintes se répètent.
  def adm_flag_class(index)
    "adm-flag adm-flag-#{index % FLAG_TONE_COUNT + 1}"
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
