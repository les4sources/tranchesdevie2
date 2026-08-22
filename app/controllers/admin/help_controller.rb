# frozen_string_literal: true

module Admin
  # Centre d'aide des boulangers (« Aide » dans la nav admin).
  # Lecture seule : le contenu vit dans app/docs/aide/*.md.
  class HelpController < Admin::BaseController
    def index
      @articles = Admin::HelpLibrary.all
      first = Admin::HelpLibrary.first
      return render :empty unless first

      redirect_to admin_help_article_path(first)
    end

    def show
      @articles = Admin::HelpLibrary.all
      @article = Admin::HelpLibrary.find(params[:slug])
      redirect_to admin_help_path unless @article
    end
  end
end
