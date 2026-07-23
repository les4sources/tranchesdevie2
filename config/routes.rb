Rails.application.routes.draw do
  # Mount Mission Control for job management
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public routes
  root "catalog#index"
  get "catalogue", to: "catalog#index", as: :catalog
  get "productions/:id", to: "products#show", as: :product
  get "a-propos", to: "pages#a_propos", as: :a_propos
  get "pizza-party-privee", to: "events#index", as: :pizza_party_privee
  get "pizza-party-publique", to: "public_parties#index", as: :pizza_party_publique
  # Ancienne URL de la page party (liens partagés / historique).
  get "evenements", to: redirect("/pizza-party-privee")
  get "conditions-generales", to: "pages#cgv", as: :cgv
  get "vie-privee", to: "pages#vie_privee", as: :vie_privee
  get "drapeaux", to: "flags#index", as: :flags

  get "panier", to: "cart#show", as: :cart
  post "cart/add", to: "cart#add", as: :cart_add
  patch "cart/update", to: "cart#update", as: :cart_update
  patch "cart/update_bake_day", to: "cart#update_bake_day", as: :cart_update_bake_day
  delete "cart/remove/:id", to: "cart#remove", as: :cart_remove
  delete "cart/logout", to: "cart#logout", as: :cart_logout

  resources :checkout, only: [ :new ] do
    collection do
      post :verify_phone
      post :verify_otp
      post :create_payment_intent
      post :create_cash_order
      post :create_wallet_order
      get :success
    end
  end

  resources :orders, only: [ :show ], param: :token

  # Customer authentication and account
  get "connexion", to: "customers/sessions#new", as: :customer_login
  post "connexion", to: "customers/sessions#create"
  delete "deconnexion", to: "customers/sessions#destroy", as: :customer_logout

  # Customer calendar (root level for cleaner URLs)
  get "calendrier", to: "customers/calendar#show", as: :calendar
  patch "calendrier/update_day", to: "customers/calendar#update_day", as: :calendar_update_day
  post "calendrier/intro/vu", to: "customers/calendar#mark_intro_seen", as: :calendar_intro_seen

  namespace :customers do
    get "mon-compte", to: "account#show", as: :account
    get "mon-compte/edit", to: "account#edit", as: :edit_account
    patch "mon-compte", to: "account#update"
    delete "mon-compte/commandes/:id", to: "account#cancel_order", as: :cancel_order
    patch "mon-compte/commandes/:id/recuperee", to: "account#pickup_order", as: :pickup_order

    # Facture PDF du détail d'une commande, téléchargeable par les clients
    # « facturables » (#38). Gating « billable » + propriété dans le contrôleur.
    get "factures/commande/:order_id", to: "invoices#order", as: :order_invoice

    # Wallet routes
    get "portefeuille", to: "wallets#show", as: :wallet
    get "portefeuille/recharger", to: "wallets#reload", as: :wallet_reload
    post "portefeuille/recharger", to: "wallets#create_reload", as: :wallet_create_reload
    get "portefeuille/success", to: "wallets#reload_success", as: :wallet_reload_success
  end

  # Email preferences (unsubscribe link in non-OTP emails — no login required, signed token)
  get "e-mails/preferences/:token", to: "email_preferences#show", as: :email_preferences
  patch "e-mails/preferences/:token", to: "email_preferences#update"

  # Webhooks
  post "/webhooks/stripe", to: "webhooks#stripe"

  # Private, read-only JSON API for AI agents.
  # Auth: Authorization: Bearer <TRANCHESDEVIE_API_KEY>. Only GET routes exist.
  namespace :api do
    namespace :v1 do
      # Agent entry points: discovery, machine spec, markdown guide.
      get "/", to: "root#index"
      get "openapi", to: "root#openapi"
      get "docs", to: "root#docs"
      get "stats", to: "stats#index"

      resources :products, only: [ :index, :show ] do
        resources :variants, only: [ :index ], controller: "product_variants"
      end
      resources :product_variants, only: [ :index, :show ]

      resources :bake_days, only: [ :index, :show ] do
        resources :orders, only: [ :index ], controller: "orders"
      end

      resources :customers, only: [ :index, :show ] do
        resources :orders, only: [ :index ], controller: "orders"
        resource :wallet, only: [ :show ], controller: "wallets"
      end

      resources :orders, only: [ :index, :show ]
      resources :payments, only: [ :index, :show ]

      resources :wallets, only: [ :index, :show ] do
        resources :transactions, only: [ :index ], controller: "wallet_transactions"
      end
      resources :wallet_transactions, only: [ :index, :show ]

      resources :groups, only: [ :index, :show ]
      resources :flours, only: [ :index, :show ]
      resources :mold_types, only: [ :index, :show ]
      resources :pickup_locations, only: [ :index, :show ]
      resources :ingredients, only: [ :index, :show ]
      resources :artisans, only: [ :index, :show ]
      resource :production_setting, only: [ :show ]
      resources :sms_messages, only: [ :index, :show ]
      resources :email_messages, only: [ :index, :show ]

      # JSON 404 for any other GET under /api/v1 (keep last).
      get "*unmatched", to: "base#not_found_route"
    end
  end

  # Admin routes
  namespace :admin do
    root to: "sessions#index"
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"

    # Centre d'aide des boulangers (doc intégrée, style GitBook).
    get "aide", to: "help#index", as: :help
    get "aide/:slug", to: "help#show", as: :help_article

    resources :reports, only: [ :index ] do
      collection do
        get :refunds
        get :baker_revenue
        get :payouts
        get :pizza_parties
      end
    end
    get "billing", to: "billing#index", as: :billing

    # Factures PDF (#38) : une commande, ou un ensemble (période / mois client).
    get "factures/commande/:order_id", to: "invoices#order", as: :order_invoice
    get "factures/periode", to: "invoices#period", as: :period_invoice

    resources :orders, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      member do
        patch :update_status
        post :refund
      end
    end

    resources :customers, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      member do
        post :send_sms
      end
      resources :sms_messages, only: [ :show ], controller: "sms_messages"
      resources :email_messages, only: [ :show ], controller: "email_messages" do
        member do
          post :resend
        end
      end
    end

    resources :groups, only: [ :index, :new, :create, :edit, :update ]

    resources :products, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      resources :variants, controller: "products", only: [ :new, :create ], param: :variant_id do
        collection do
          get :new, action: :new_variant, as: :new
          post :create, action: :create_variant, as: :create
        end
      end

      member do
        get "variants/:variant_id", to: "products#show_variant", as: :variant
        get "variants/:variant_id/edit", to: "products#edit_variant", as: :edit_variant
        patch "variants/:variant_id", to: "products#update_variant"
        delete "variants/:variant_id", to: "products#destroy_variant"
        patch "variants/:variant_id/reorder_images", to: "products#reorder_variant_images", as: :reorder_variant_images
      end
    end

    resources :bake_days, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
      member do
        get :confirm_cancel
        post :cancel
        # Feuille d'émargement PDF d'un point de retrait (#148), paramétrée par
        # ?pickup_location_id= — même pattern que Admin::InvoicesController.
        get :pickup_sheet
        # Feuille compta (#feuille-compta) : reporting tableur par jour de cuisson
        # (validation des chiffres boulangers/4S, format feuille de Stéphanie).
        get :sheet
      end
    end

    # Points de retrait (#148) : CRUD + cochage des fournées ouvertes.
    resources :pickup_locations, path: "points-de-retrait",
      only: [ :index, :new, :create, :edit, :update, :destroy ]

    # Événements party (#pizza-parties) : événements publics (CRUD) + blocages de
    # créneaux des parties privées.
    resources :party_events, path: "parties", except: [ :show ]
    resources :party_slot_blocks, path: "parties/blocages", only: [ :index, :create, :destroy ]

    get "parametres", to: "settings#index", as: :settings
    scope path: "parametres", as: "settings", module: "settings" do
      resources :flours, path: "farines"
      resources :artisans do
        resources :revenue_shares, only: [ :index, :new, :create, :edit, :update, :destroy ],
                                   controller: "artisan_revenue_shares", path: "parts-de-revenu"
      end
      # Partenariats de revenu (#54) : regroupent des artisans qui mettent en
      # commun leur revenu brut puis se le répartissent (ex. Romane & Stéphanie
      # à 50/50).
      resources :revenue_partnerships, path: "partenariats",
                only: [ :index, :new, :create, :edit, :update, :destroy ]
      resources :ingredients
      resources :mold_types, path: "types-de-moules"
      resource :production_setting, path: "capacites-de-production", only: [ :edit, :update ]
      # Message « commande prête » éditable (SMS + email) — page « Notifications ».
      resource :notification_setting, path: "notifications", only: [ :edit, :update ]
      # Paramètres généraux historisés du calcul des revenus boulangers (#54) :
      # transport (15 €/jour) et taux 4 Sources (30 %). Un seul contrôleur gère
      # les deux clés via le paramètre `:key`.
      resources :revenue_parameters, path: "revenus-boulangers", only: [ :index, :new, :create, :edit, :update, :destroy ]
      # Lieux de vente (#150) : CRUD + coûts historisés par période de validité.
      resources :sales_locations, path: "lieux-de-vente" do
        resources :sales_location_costs, controller: "sales_location_costs",
          path: "couts", only: [ :index, :new, :create, :edit, :update, :destroy ]
      end
    end
  end
end
