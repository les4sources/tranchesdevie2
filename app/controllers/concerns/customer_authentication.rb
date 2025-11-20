module CustomerAuthentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_customer, :customer_signed_in?
  end

  private

  def authenticate_customer!
    return if customer_signed_in?

    redirect_to customer_login_path, alert: 'Veuillez vous connecter'
  end

  def current_customer
    return nil unless session[:customer_id].present?
    return nil unless session[:customer_authenticated_at].present?

    # Vérifier que la session n'a pas expiré (1 an)
    authenticated_at = Time.at(session[:customer_authenticated_at])
    return nil if authenticated_at < 1.year.ago

    @current_customer ||= Customer.find_by(id: session[:customer_id])
  end

  def customer_signed_in?
    current_customer.present?
  end
end

