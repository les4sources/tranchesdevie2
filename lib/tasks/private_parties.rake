namespace :private_parties do
  desc "Convertit en parties privées les pizza parties enregistrées comme commandes de pain. " \
       "SIMULATION par défaut ; CONFIRM=1 pour écrire. Options : IDS=627,630 (limiter) " \
       "DATES=627:2026-07-12:soir,630:2026-08-01 (imposer date/créneau)."
  task convert_legacy_orders: :environment do
    order_ids = ENV["IDS"].to_s.split(",").map(&:strip).reject(&:empty?)
    overrides = ENV["DATES"].to_s.split(",").each_with_object({}) do |entry, map|
      id, date, slot = entry.strip.split(":")
      next if id.blank? || date.blank?

      map[id.to_i] = { held_on: Date.iso8601(date), slot: slot.presence }.compact
    rescue ArgumentError
      abort("DATES : date invalide dans « #{entry} » (format attendu 627:AAAA-MM-JJ[:soir|midi])")
    end
    confirm = ENV["CONFIRM"] == "1"

    service = LegacyPrivatePartyConversionService.new(order_ids: order_ids, overrides: overrides)
    candidates = service.candidates
    convertible, skipped = candidates.partition(&:convertible?)

    euros = ->(cents) { format("%.2f €", cents.to_i / 100.0).tr(".", ",") }
    payment = lambda do |order|
      method = order.payment_method
      label = { stripe: "Stripe", wallet: "Portefeuille", cash: "Liquide", transfer: "Virement",
                online: "En ligne", with_stay: "Avec le séjour" }[method&.to_sym]
      status = { "paid" => "payée", "unpaid" => "non payée", "refunded" => "remboursée" }.fetch(order.payment_status, order.payment_status)
      [ status, label && "(#{label})" ].compact.join(" ")
    end

    puts confirm ? "=== CONVERSION (écriture) ===" : "=== SIMULATION (rien n'est écrit — CONFIRM=1 pour convertir) ==="
    puts ""
    puts "À convertir : #{convertible.size}"
    convertible.each do |c|
      order = c.order
      moved = order.bake_day && c.held_on != order.bake_day.baked_on ? " (fournée d'origine #{order.bake_day.baked_on})" : ""
      puts "  ##{order.id} #{order.order_number} — #{order.customer&.full_name} — party du #{c.held_on} #{c.slot}#{moved}"
      puts "      #{c.persons} pers. · forfait #{c.forfait ? 'oui' : 'non'} · #{euros.call(order.total_cents)} · " \
           "statut #{order.status} · #{payment.call(order)} · source #{order.source}"
      puts "      note : #{order.customer_note.to_s.squish.truncate(140)}" if order.customer_note.present?
    end

    if skipped.any?
      puts ""
      puts "Ignorées : #{skipped.size}"
      skipped.each do |c|
        order = c.order
        puts "  ##{order.id} #{order.order_number} — #{order.customer&.full_name} — " \
             "#{order.bake_day&.baked_on || '?'} — #{euros.call(order.total_cents)} — #{c.reason}"
      end
    end

    next unless confirm

    converted = service.call
    puts ""
    puts "#{converted.size} commande(s) convertie(s) en party privée."
  end
end
