# frozen_string_literal: true

module Admin
  module HelpHelper
    # Options de rendu commonmarker : GFM (tables, barré, autolien, cases à
    # cocher), notes de bas de page, ancres de titres pour le sommaire interne.
    MARKDOWN_OPTIONS = {
      extension: {
        table: true,
        strikethrough: true,
        autolink: true,
        tasklist: true,
        footnotes: true,
        header_ids: ""
      },
      render: { unsafe: false, hardbreaks: false }
    }.freeze

    ASSET_DIR = Rails.root.join("app", "assets", "images", "aide")

    # Rend un chapitre markdown en HTML enrichi :
    #  - les images `![légende](shot:slug)` deviennent des captures d'écran
    #    (fichier `app/assets/images/aide/slug.png`) encadrées + légendées, ou
    #    un placeholder « capture à générer » si le PNG n'existe pas encore.
    def render_help_markdown(markdown)
      html = Commonmarker.to_html(markdown.to_s, options: MARKDOWN_OPTIONS)
      doc = Nokogiri::HTML5.fragment(html)

      doc.css("img").each do |img|
        src = img["src"].to_s
        next unless src.start_with?("shot:")

        slug = src.delete_prefix("shot:").strip
        img.replace(help_screenshot_figure(slug, img["alt"]))
      end

      doc.to_html.html_safe
    end

    # Existe-t-il une capture pour ce slug ?
    def help_screenshot_exists?(slug)
      ASSET_DIR.join("#{slug}.png").file?
    end

    private

    def help_screenshot_figure(slug, caption)
      caption = caption.to_s.strip

      if help_screenshot_exists?(slug)
        image = image_tag(
          "aide/#{slug}.png",
          alt: caption.presence || slug,
          loading: "lazy",
          class: "w-full rounded-lg border border-gray-200 shadow-sm"
        )
      else
        image = content_tag(
          :div,
          "📷 Capture à générer : #{slug}",
          class: "flex items-center justify-center rounded-lg border-2 border-dashed border-gray-300 bg-gray-50 px-4 py-10 text-sm text-gray-400"
        )
      end

      figcaption = caption.present? ? content_tag(:figcaption, caption, class: "mt-2 text-center text-sm text-gray-500") : "".html_safe
      content_tag(:figure, image + figcaption, class: "aide-shot my-6")
    end
  end
end
