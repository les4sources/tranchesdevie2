RSpec.configure do |config|
  # Pilotage réel du calculateur de fournées (#194) via Selenium : exclu du run
  # normal comme les captures du centre d'aide, parce qu'il exige Chrome.
  # Lancer avec : bundle exec rspec spec/system --tag batch_planner_ui
  config.filter_run_excluding :batch_planner_ui
end
