RSpec.configure do |config|
  # Specs qui pilotent un vrai navigateur (Selenium) : exclues du run normal,
  # comme les captures du centre d'aide, parce qu'elles exigent Chrome.
  # Lancer avec : bundle exec rspec spec/system --tag browser_ui
  config.filter_run_excluding :browser_ui
end
