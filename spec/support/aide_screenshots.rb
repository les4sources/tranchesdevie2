# frozen_string_literal: true

# Le spec `spec/screenshots/aide_screenshots_spec.rb` n'est pas un test : c'est
# le générateur des captures du centre d'aide (piloté par `bin/rails
# aide:screenshots`). On l'exclut du run normal ; la tâche rake le réactive avec
# `--tag aide_screenshots` (la ligne de commande a la priorité sur cette
# exclusion).
RSpec.configure do |config|
  config.filter_run_excluding :aide_screenshots
end
