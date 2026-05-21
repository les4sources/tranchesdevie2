# Public email-preferences page reachable from the footer link of non-OTP
# emails. Identified by a signed token (no login required).
class EmailPreferencesController < ApplicationController
  def show
    @customer = find_customer
    redirect_to root_path, alert: "Ce lien n'est plus valide." unless @customer
  end

  def update
    @customer = find_customer
    return redirect_to(root_path, alert: "Ce lien n'est plus valide.") unless @customer

    opt_out = ActiveModel::Type::Boolean.new.cast(params[:email_opt_out])
    @customer.update(email_opt_out: opt_out)

    notice =
      if @customer.email_opt_out?
        "Tu ne recevras plus d'e-mails de notre part (hors codes de connexion)."
      else
        "C'est noté, tu es réabonné·e à nos e-mails."
      end
    redirect_to email_preferences_path(token: params[:token]), notice: notice
  end

  private

  def find_customer
    Customer.find_signed(params[:token], purpose: :email_unsubscribe)
  end
end
