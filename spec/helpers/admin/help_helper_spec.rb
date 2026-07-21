require "rails_helper"
require "fileutils"
require "tmpdir"

RSpec.describe Admin::HelpHelper, type: :helper do
  before do
    @asset_dir = Pathname.new(Dir.mktmpdir("aide-assets-specs"))
    stub_const("Admin::HelpHelper::ASSET_DIR", @asset_dir)
  end

  after do
    FileUtils.remove_entry(@asset_dir) if @asset_dir&.directory?
  end

  describe "#render_help_markdown" do
    it "renders headings, lists, and GFM tables" do
      html = helper.render_help_markdown(<<~MD)
        # Titre

        - Une ligne

        | Colonne A | Colonne B |
        | --- | --- |
        | Pain | Levain |
      MD

      fragment = Nokogiri::HTML5.fragment(html)

      expect(fragment.at_css("h1").text).to eq("Titre")
      expect(fragment.at_css("ul li").text).to eq("Une ligne")
      expect(fragment.at_css("table td").text).to eq("Pain")
    end

    it "renders a placeholder figure for missing screenshot assets" do
      html = helper.render_help_markdown("![légende](shot:missing-slug)")
      fragment = Nokogiri::HTML5.fragment(html)
      figure = fragment.at_css("figure.aide-shot")

      expect(figure).to be_present
      expect(figure.at_css("div")["class"]).to include("border-dashed")
      expect(figure.at_css("div").text).to include("📷 Capture à générer : missing-slug")
      expect(figure.at_css("figcaption").text).to eq("légende")
      expect(figure.at_css("img")).to be_nil
    end

    it "returns html-safe output" do
      html = helper.render_help_markdown("# Titre")

      expect(html).to be_html_safe
    end
  end

  describe "#help_screenshot_exists?" do
    it "returns false when no PNG exists for the slug" do
      expect(helper.help_screenshot_exists?("missing-slug")).to be(false)
    end

    it "returns true when a PNG exists for the slug" do
      @asset_dir.join("present-slug.png").write("png")

      expect(helper.help_screenshot_exists?("present-slug")).to be(true)
    end
  end
end
