# frozen_string_literal: true

# Centre d'aide des boulangers — bibliothèque des articles markdown.
#
# La source de vérité est un dossier de fichiers markdown (`app/docs/aide/*.md`),
# un fichier par chapitre, avec un front-matter YAML :
#
#     ---
#     title: Les commandes
#     order: 2
#     icon: "🧾"
#     summary: Suivre, préparer et encaisser les commandes du jour.
#     ---
#     # Les commandes
#     ...
#
# On rend le tout dans l'admin (layout GitBook : sommaire à gauche, contenu à
# droite). Aucune donnée en base : éditer un chapitre = éditer son `.md`.
module Admin
  class HelpLibrary
    DOCS_DIR = Rails.root.join("app", "docs", "aide")
    FRONT_MATTER = /\A---\s*\n(?<yaml>.*?)\n---\s*\n(?<body>.*)\z/m

    # Un chapitre du centre d'aide.
    Article = Data.define(:slug, :title, :order, :icon, :summary, :body) do
      def to_param = slug
    end

    class << self
      # Tous les chapitres, triés par `order` puis titre. Résultat mémoïsé en
      # production, rechargé à chaque appel en développement pour voir les édits.
      def all
        return @all if @all && !Rails.env.development?

        @all = load_articles
      end

      # Un chapitre par slug, ou nil.
      def find(slug)
        all.find { |a| a.slug == slug.to_s }
      end

      # Le premier chapitre (sert de page d'accueil du centre d'aide).
      def first
        all.first
      end

      def reset! # utilisé par les specs
        @all = nil
      end

      private

      def load_articles
        return [] unless DOCS_DIR.directory?

        DOCS_DIR.glob("*.md").filter_map { |path| build_article(path) }
                .sort_by { |a| [ a.order, a.title ] }
      end

      def build_article(path)
        raw = path.read
        match = raw.match(FRONT_MATTER)
        # Le découpage front-matter/corps (regex) ne peut pas échouer ; seul le
        # parse YAML le peut. Dans ce cas on garde le chapitre visible avec des
        # valeurs de repli (titre depuis le nom de fichier) plutôt que de le
        # faire disparaître en silence.
        meta = match ? safe_yaml(match[:yaml], path) : {}
        body = match ? match[:body] : raw

        slug = path.basename(".md").to_s
        Article.new(
          slug: slug,
          title: meta["title"].presence || slug.humanize,
          order: (meta["order"] || 999).to_i,
          icon: meta["icon"].presence,
          summary: meta["summary"].presence,
          body: body.to_s.strip
        )
      rescue => e
        Rails.logger.error("[HelpLibrary] Impossible de charger #{path}: #{e.message}")
        nil
      end

      def safe_yaml(yaml, path)
        YAML.safe_load(yaml) || {}
      rescue Psych::SyntaxError => e
        Rails.logger.error("[HelpLibrary] Front-matter YAML invalide dans #{path} (#{e.message}). " \
                           "Astuce : mets les valeurs contenant « : » entre guillemets.")
        {}
      end
    end
  end
end
