# frozen_string_literal: true

# Rake tasks pour la génération automatique de la documentation boulanger.
#
#   rake docs:seed_demo        # remplit la DB de test avec des données démo
#   rake docs:screenshots      # (seeds + serveur Rails + Playwright) → PNG dans docs/admin/images/
#   rake docs:server           # démarre juste le serveur en mode démo (utile en dev)

namespace :docs do
  DOCS_ROOT   = Rails.root.join("docs/admin")
  IMAGES_DIR  = DOCS_ROOT.join("images")
  SEED_FILE   = Rails.root.join("db/seeds/demo.rb")
  MANIFEST    = Rails.root.join("script/docs/screenshot_manifest.yml")
  PLAYWRIGHT  = Rails.root.join("script/docs/generate_screenshots.mjs")
  DEMO_PORT   = ENV.fetch("DOCS_PORT", "4567").to_i
  DEMO_HOST   = "127.0.0.1"

  desc "Charge le jeu de seeds démo pour la génération de captures d'écran"
  task seed_demo: :environment do
    guard_environment!
    load SEED_FILE.to_s
    puts "Seeds démo chargés (RAILS_ENV=#{Rails.env})."
  end

  desc "Démarre un serveur Rails avec les seeds démo (Ctrl+C pour arrêter)"
  task server: :environment do
    guard_environment!
    load SEED_FILE.to_s
    exec Rails.root.join("bin/rails").to_s, "server", "-b", DEMO_HOST, "-p", DEMO_PORT.to_s
  end

  desc "Regénère toutes les captures d'écran de docs/admin/images/"
  task screenshots: :environment do
    guard_environment!
    load SEED_FILE.to_s

    require "socket"
    if port_open?(DEMO_HOST, DEMO_PORT)
      abort "❌ Le port #{DEMO_PORT} est occupé. Fermez le processus qui l'utilise et recommencez."
    end

    server_pid = spawn(
      { "RAILS_ENV" => Rails.env, "ADMIN_PASSWORD" => admin_password },
      Rails.root.join("bin/rails").to_s, "server", "-b", DEMO_HOST, "-p", DEMO_PORT.to_s,
      pgroup: true, out: "/tmp/docs-rails.log", err: "/tmp/docs-rails.log"
    )

    begin
      wait_for_server!(DEMO_HOST, DEMO_PORT)
      puts "✅ Serveur Rails prêt sur http://#{DEMO_HOST}:#{DEMO_PORT}"
      env = {
        "DOCS_BASE_URL"     => "http://#{DEMO_HOST}:#{DEMO_PORT}",
        "DOCS_ADMIN_PWD"    => admin_password,
        "DOCS_MANIFEST"     => MANIFEST.to_s,
        "DOCS_OUTPUT_DIR"   => IMAGES_DIR.to_s
      }
      unless system(env, "node", PLAYWRIGHT.to_s)
        abort "❌ La génération des captures a échoué. Voir /tmp/docs-rails.log."
      end
      puts "✅ Captures d'écran regénérées dans #{IMAGES_DIR}"
    ensure
      begin
        Process.kill("-TERM", Process.getpgid(server_pid))
        Process.wait(server_pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # already gone
      end
    end
  end

  # -- helpers -------------------------------------------------------------

  def guard_environment!
    return if Rails.env.test?
    return if ENV["DOCS_ALLOW_UNSAFE"] == "1"

    abort <<~MSG
      ❌ Ces tâches manipulent la base de données et ne doivent tourner qu'en
         environnement `test`. Relancez avec :
             RAILS_ENV=test bundle exec rake #{Rake.application.top_level_tasks.first}
         Pour forcer une exécution ailleurs (à vos risques),
             DOCS_ALLOW_UNSAFE=1 rake #{Rake.application.top_level_tasks.first}
    MSG
  end

  def admin_password
    ENV["ADMIN_PASSWORD"].presence || "demo"
  end

  def port_open?(host, port)
    Socket.tcp(host, port, connect_timeout: 0.3) { true }
  rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT
    false
  end

  def wait_for_server!(host, port, timeout: 30)
    deadline = Time.now + timeout
    loop do
      break if port_open?(host, port)
      raise "Le serveur Rails n'a pas démarré en #{timeout}s" if Time.now > deadline
      sleep 0.4
    end
  end
end
