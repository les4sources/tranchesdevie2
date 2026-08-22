# frozen_string_literal: true

module Admin
  module Settings
    class NotificationSettingsController < Admin::BaseController
      def edit
        @notification_setting = NotificationSetting.current
      end

      def update
        @notification_setting = NotificationSetting.current

        if @notification_setting.update(notification_setting_params)
          redirect_to admin_settings_path, notice: "Message de notification mis à jour"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      private

      def notification_setting_params
        params.require(:notification_setting).permit(
          :ready_sms_body, :ready_sms_body_unpaid, :ready_email_subject
        )
      end
    end
  end
end
