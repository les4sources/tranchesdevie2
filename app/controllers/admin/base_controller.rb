class Admin::BaseController < ApplicationController
  layout "admin"
  helper Admin::FormHelper
  before_action :authenticate_admin!

  private

  def authenticate_admin!
    if admin_authenticated?
      # Prolonge la session à chaque accès (expiration glissante).
      session[:admin_authenticated_at] = Time.current.to_s
      return
    end

    redirect_to admin_login_path, alert: "Veuillez vous connecter"
  end

  def authenticate_admin_password(password)
    expected_password = ENV["ADMIN_PASSWORD"]
    return false if expected_password.blank?

    ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
  end
end
