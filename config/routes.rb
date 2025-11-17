Rails.application.routes.draw do
  # Mount Mission Control for job management
  mount MissionControl::Jobs::Engine, at: "/admin/jobs"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # Public routes
  root "catalog#index"
  get "catalog", to: "catalog#index"

  get "cart", to: "cart#show", as: :cart
  post "cart/add", to: "cart#add", as: :cart_add
  patch "cart/update", to: "cart#update", as: :cart_update
  patch "cart/update_bake_day", to: "cart#update_bake_day", as: :cart_update_bake_day
  delete "cart/remove/:id", to: "cart#remove", as: :cart_remove

  resources :checkout, only: [:new] do
    collection do
      post :verify_phone
      post :verify_otp
      post :create_payment_intent
      get :success
    end
  end

  resources :orders, only: [:show], param: :token

  # Webhooks
  post "/webhooks/stripe", to: "webhooks#stripe"
  post "/webhooks/telerivet", to: "webhooks#telerivet"

  # Admin routes
  namespace :admin do
    get "login", to: "sessions#new"
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy"

    resources :reports, only: [:index]

    resources :orders, only: [:index, :show] do
      member do
        patch :update_status
        post :refund
      end
    end

    resources :products, only: [:index, :show, :new, :create, :edit, :update, :destroy] do
      resources :variants, controller: "products", only: [:new, :create], param: :variant_id do
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
      end
    end

    resources :bake_days, only: [:index, :show, :new, :create, :edit, :update, :destroy]
  end
end
