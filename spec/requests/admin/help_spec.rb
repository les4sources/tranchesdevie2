require "rails_helper"
require "fileutils"
require "tmpdir"

RSpec.describe "Admin help", type: :request do
  around do |ex|
    original = ENV['ADMIN_PASSWORD']
    ENV['ADMIN_PASSWORD'] = 'test-admin-pw'
    ex.run
    ENV['ADMIN_PASSWORD'] = original
  end

  before do
    @docs_dir = Pathname.new(Dir.mktmpdir("aide-request-specs"))
    stub_const("Admin::HelpLibrary::DOCS_DIR", @docs_dir)
    Admin::HelpLibrary.reset!
  end

  after do
    Admin::HelpLibrary.reset!
    FileUtils.remove_entry(@docs_dir) if @docs_dir&.directory?
  end

  def login_admin
    post admin_login_path, params: { password: 'test-admin-pw' }
  end

  def write_article(slug, content)
    @docs_dir.join("#{slug}.md").write(content)
  end

  it "redirects unauthenticated visitors to the admin login page" do
    get admin_help_path

    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(admin_login_path)
  end

  context "when authenticated" do
    before { login_admin }

    it "redirects the help index to the first article when articles exist" do
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

      get admin_help_path

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(admin_help_article_path("first"))
    end

    it "renders the empty help page when no articles exist" do
      get admin_help_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Aucun chapitre d'aide n'est encore disponible.")
    end

    it "renders a valid help article" do
      write_article("valid-slug", <<~MD)
        ---
        title: Article rendu
        order: 1
        summary: Résumé visible.
        ---
        # Contenu rendu

        Un paragraphe spécifique.
      MD

      get admin_help_article_path("valid-slug")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Article rendu")
      expect(response.body).to include("Résumé visible.")
      expect(response.body).to include("Contenu rendu")
      expect(response.body).to include("Un paragraphe spécifique.")
    end

    it "redirects an unknown help article slug to the help index" do
      get admin_help_article_path("nope")

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(admin_help_path)
    end
  end
end
