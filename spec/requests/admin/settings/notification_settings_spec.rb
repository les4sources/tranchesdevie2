require 'rails_helper'

RSpec.describe 'Admin::Settings::NotificationSettings', type: :request do
  around do |ex|
    original = ENV['ADMIN_PASSWORD']
    ENV['ADMIN_PASSWORD'] = 'test-admin-pw'
    ex.run
    ENV['ADMIN_PASSWORD'] = original
  end

  def login_admin
    post admin_login_path, params: { password: 'test-admin-pw' }
  end

  it 'requires admin authentication' do
    get edit_admin_settings_notification_setting_path
    expect(response).to redirect_to(admin_login_path)
  end

  context 'when authenticated' do
    before { login_admin }

    it 'renders the edit page with the current message pre-filled' do
      get edit_admin_settings_notification_setting_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Bonjour, ta commande')
    end

    it 'persists an updated message' do
      patch admin_settings_notification_setting_path, params: {
        notification_setting: {
          ready_sms_body: 'Nouveau message prêt',
          ready_sms_body_unpaid: 'Non payé, total {montant}',
          ready_email_subject: 'Objet perso'
        }
      }
      expect(response).to redirect_to(admin_settings_path)
      setting = NotificationSetting.current
      expect(setting.ready_sms_body).to eq('Nouveau message prêt')
      expect(setting.ready_sms_body_unpaid).to eq('Non payé, total {montant}')
      expect(setting.ready_email_subject).to eq('Objet perso')
    end
  end
end
