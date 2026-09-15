require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Tranchesdevie2
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = "Europe/Brussels"
    config.active_record.default_timezone = :local

    # i18n configuration
    config.i18n.available_locales = [ :fr, :nl, :en ]
    config.i18n.default_locale = :fr
    config.i18n.fallbacks = [ :fr ]

    # ActiveJob configuration
    config.active_job.queue_adapter = :solid_queue

    # Rack::Attack middleware for rate limiting
    config.middleware.use Rack::Attack

    config.autoload_paths << Rails.root.join("app/presenters")
    config.eager_load_paths << Rails.root.join("app/presenters")
    config.autoload_paths << Rails.root.join("app/decorators")
    config.eager_load_paths << Rails.root.join("app/decorators")

    # Variantes Active Storage : ImageMagick, pas vips (TRANCHESDEVIE-1A).
    #
    # Rails utilise :vips par défaut, et le charge AU BOOT (ActiveStorage
    # after_initialize → Transformers::Vips → require "vips"). Le serveur de
    # production n'a pas la bibliothèque C libvips : depuis le passage de
    # image_processing à 2.x, le boot de l'environnement production levait donc
    # un LoadError, `assets:precompile` échouait, et AUCUN déploiement ne
    # basculait — la prod est restée figée sur la release du 14/09 20h52 pendant
    # que les releases suivantes se construisaient dans le vide.
    #
    # ImageMagick est installé sur le serveur (6.9.11) : on s'appuie dessus.
    config.active_storage.variant_processor = :mini_magick

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
