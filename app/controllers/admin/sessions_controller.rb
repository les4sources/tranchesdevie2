class Admin::SessionsController < ApplicationController
  layout 'admin'

  def index
    if admin_authenticated?
      redirect_to admin_orders_path
    else
      redirect_to admin_login_path
    end
  end

  def new
    redirect_to admin_orders_path if admin_authenticated?
  end

  def create
    password = params[:password]

    if authenticate_admin_password(password)
      session[:admin_authenticated] = true
      session[:admin_authenticated_at] = Time.current.to_s
      redirect_to admin_orders_path, notice: 'Connexion réussie'
    else
      redirect_to admin_login_path, alert: 'Mot de passe incorrect'
    end
  end

  def destroy
    session[:admin_authenticated] = nil
    session[:admin_authenticated_at] = nil
    redirect_to admin_login_path, notice: 'Déconnexion réussie'
  end

  private

  def authenticate_admin_password(password)
    expected_password = ENV['ADMIN_PASSWORD']
    return false if expected_password.blank?

    ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
  end

  def admin_authenticated?
    session[:admin_authenticated] == true &&
      session[:admin_authenticated_at] &&
      Time.current - Time.parse(session[:admin_authenticated_at]) < 24.hours
  end
end

