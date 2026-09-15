require 'rails_helper'

# Polyfill des import maps (TRANCHESDEVIE-19).
#
# Safari 16.3 et antérieur ne gère pas les import maps : sans es-module-shims,
# « import "application" » lève un TypeError et TOUT le JavaScript du site meurt
# — panier, saisie du GSM, paiement Stripe. Le client ne peut plus commander, et
# rien n'en paraît côté serveur. Le shim doit donc être chargé AVANT le module.
RSpec.describe 'Polyfill des import maps', type: :request do
  it 'charge es-module-shims avant le script module, sur la boutique' do
    get root_path

    expect(response.body).to include('es-module-shims')
    shim_at = response.body.index('es-module-shims')
    module_at = response.body.index('type="importmap"')
    expect(shim_at).to be < module_at
  end

  it 'le charge aussi sur la page de connexion' do
    get customer_login_path

    expect(response.body).to include('es-module-shims')
  end
end
