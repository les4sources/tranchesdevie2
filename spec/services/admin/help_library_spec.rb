require "rails_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Admin::HelpLibrary do
  before do
    @docs_dir = Pathname.new(Dir.mktmpdir("aide-specs"))
    stub_const("Admin::HelpLibrary::DOCS_DIR", @docs_dir)
    described_class.reset!
  end

  after do
    described_class.reset!
    FileUtils.remove_entry(@docs_dir) if @docs_dir&.directory?
  end

  def write_article(slug, content)
    @docs_dir.join("#{slug}.md").write(content)
  end

  describe ".all" do
    it "loads markdown files as article values with slugs and params" do
      write_article("prise-en-main", <<~MD)
        ---
        title: Prise en main
        order: 1
        icon: "📖"
        summary: Démarrer avec le centre d'aide.
        ---
        # Bienvenue
      MD

      article = described_class.all.sole

      expect(article).to be_a(Admin::HelpLibrary::Article)
      expect(article.slug).to eq("prise-en-main")
      expect(article.title).to eq("Prise en main")
      expect(article.order).to eq(1)
      expect(article.icon).to eq("📖")
      expect(article.summary).to eq("Démarrer avec le centre d'aide.")
      expect(article.body).to eq("# Bienvenue")
      expect(article.to_param).to eq("prise-en-main")
    end

    it "sorts articles by order, then by title" do
      write_article("z-last", <<~MD)
        ---
        title: Zèbre
        order: 20
        ---
        Z
      MD
      write_article("first", <<~MD)
        ---
        title: Premier
        order: 10
        ---
        P
      MD
      write_article("a-before-z", <<~MD)
        ---
        title: Abricot
        order: 20
        ---
        A
      MD

      expect(described_class.all.map(&:title)).to eq([ "Premier", "Abricot", "Zèbre" ])
    end

    it "parses YAML front matter and strips it from the body" do
      write_article("commandes", <<~MD)
        ---
        title: Les commandes
        order: 2
        icon: "🧾"
        summary: Suivre les commandes du jour.
        ---
        # Suivre

        Le corps du chapitre.
      MD

      article = described_class.all.sole

      expect(article.title).to eq("Les commandes")
      expect(article.order).to eq(2)
      expect(article.icon).to eq("🧾")
      expect(article.summary).to eq("Suivre les commandes du jour.")
      expect(article.body).to eq("# Suivre\n\nLe corps du chapitre.")
      expect(article.body).not_to include("---", "title:", "summary:")
    end

    it "uses fallback metadata when front matter is missing" do
      write_article("sans-front-matter", <<~MD)
        # Titre brut

        Corps sans métadonnées.
      MD

      article = described_class.all.sole

      expect(article.title).to eq("sans-front-matter".humanize)
      expect(article.order).to eq(999)
      expect(article.icon).to be_nil
      expect(article.summary).to be_nil
      expect(article.body).to eq("# Titre brut\n\nCorps sans métadonnées.")
    end

    it "returns an empty array when the docs directory is empty" do
      expect(described_class.all).to eq([])
      expect(described_class.first).to be_nil
    end

    it "returns an empty array when the docs directory is absent" do
      FileUtils.remove_entry(@docs_dir)
      described_class.reset!

      expect(described_class.all).to eq([])
      expect(described_class.first).to be_nil
    end

    it "garde un fichier au front-matter YAML invalide plutôt que de le faire disparaître (résilience)" do
      write_article("valid", <<~MD)
        ---
        title: Valide
        order: 1
        ---
        Contenu valide.
      MD
      write_article("broken", <<~MD)
        ---
        title: [yaml cassé
        ---
        Ce fichier doit rester visible.
      MD

      articles = described_class.all

      # Le fichier valide charge normalement ; le fichier cassé reste visible
      # avec un titre de repli dérivé du nom de fichier (pas de disparition
      # silencieuse), et son corps est préservé.
      expect(articles.map(&:slug)).to contain_exactly("valid", "broken")
      broken = articles.find { |a| a.slug == "broken" }
      expect(broken.title).to eq("broken".humanize)
      expect(broken.summary).to be_nil
      expect(broken.body).to eq("Ce fichier doit rester visible.")
    end
  end

  describe ".find" do
    before do
      write_article("valid-slug", <<~MD)
        ---
        title: Article valide
        order: 1
        ---
        Contenu.
      MD
    end

    it "returns the matching article for a string slug" do
      expect(described_class.find("valid-slug").title).to eq("Article valide")
    end

    it "returns nil for an unknown slug" do
      expect(described_class.find("does-not-exist")).to be_nil
    end

    it "accepts a symbol slug" do
      expect(described_class.find(:"valid-slug").slug).to eq("valid-slug")
    end
  end

  describe ".first" do
    it "returns the lowest-order article" do
      write_article("second", <<~MD)
        ---
        title: Deuxième
        order: 2
        ---
        Deuxième.
      MD
      write_article("first", <<~MD)
        ---
        title: Premier
        order: 1
        ---
        Premier.
      MD

      expect(described_class.first.slug).to eq("first")
    end
  end
end
