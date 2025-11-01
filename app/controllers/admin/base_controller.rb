class Admin::BaseController < ApplicationController
  layout 'admin'
  before_action :authenticate_admin!

  private

  def authenticate_admin!
    return if admin_authenticated?

    redirect_to admin_login_path, alert: 'Veuillez vous connecter'
  end

  def admin_authenticated?
    session[:admin_authenticated] == true &&
      session[:admin_authenticated_at] &&
      Time.current - Time.parse(session[:admin_authenticated_at]) < 24.hours
  end

  def authenticate_admin_password(password)
    expected_password = ENV['ADMIN_PASSWORD']
    return false if expected_password.blank?

    ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
  end
end

