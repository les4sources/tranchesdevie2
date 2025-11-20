class Admin::SmsMessagesController < Admin::BaseController
  before_action :set_customer
  before_action :set_sms_message

  def show
  end

  private

  def set_customer
    @customer = Customer.find(params[:customer_id])
  end

  def set_sms_message
    @sms_message = @customer.sms_messages.find(params[:id])
  end
end

