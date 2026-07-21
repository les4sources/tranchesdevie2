# frozen_string_literal: true

namespace :aide do
  desc "Régénère les captures d'écran du centre d'aide boulangers (Selenium headless, données de démo anonymisées)"
  task :screenshots do
    puts "→ Génération des captures du centre d'aide (Selenium headless)…"
    cmd = "bundle exec rspec spec/screenshots/aide_screenshots_spec.rb --tag aide_screenshots"
    puts "  #{cmd}"
    system(cmd) || abort("✗ Échec de la génération des captures.")
    puts "✓ Captures à jour dans app/assets/images/aide/"
    puts "  Pense à les committer (elles font partie de la doc)."
  end
end
