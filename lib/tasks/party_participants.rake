namespace :party_participants do
  desc "Importe la liste nominative des participants d'une party depuis un export de billetterie (CSV). " \
       "Usage : bin/rails party_participants:import EVENT_ID=12 FILE=/chemin/export.csv"
  task import: :environment do
    event_id = ENV["EVENT_ID"]
    path = ENV["FILE"]

    abort("EVENT_ID est requis (bin/rails party_participants:import EVENT_ID=12 FILE=/chemin/export.csv)") if event_id.blank?
    abort("FILE est requis (chemin du CSV exporté ; il n'est jamais versionné)") if path.blank?

    event = PartyEvent.find_by(id: event_id)
    abort("Aucun événement party ##{event_id}") if event.nil?

    puts "Import des participants de « #{event.title.presence || 'party'} » du #{I18n.l(event.held_on)}"
    puts "Fichier : #{path}"
    puts ""

    importer = PartyParticipantImporter.new(party_event: event, path: path)
    result = importer.call

    if result.nil?
      warn "Échec : #{importer.errors.join(' · ')}"
      exit 1
    end

    importer.errors.each { |message| warn "  ⚠ #{message}" }

    puts result.summary
    puts ""
    puts "Rappel : aucune commande n'a été créée, et la comptabilité de cet événement"
    puts "reste celle de l'agrégat (#{event.historical_adults || 0} adultes / #{event.historical_children || 0} enfants" \
         " / #{event.historical_sourciers || 0} sourciers)."
  end
end
