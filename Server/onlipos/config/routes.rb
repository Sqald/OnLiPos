Rails.application.routes.draw do
  # ヘルスチェック用（config.silence_healthcheck_path / ssl_options の除外設定が /up を前提にしている）
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: [ :confirmations, :unlocks, :passwords, :omniauth_callbacks ], controllers: { sessions: "users/sessions" }
  # ダッシュボードログインの2段階目（多要素認証）。パスワード確認後にのみ使える
  devise_scope :user do
    get    "users/mfa",                 to: "users/mfa#show",            as: :user_mfa
    delete "users/mfa",                 to: "users/mfa#cancel",          as: :cancel_user_mfa
    post   "users/mfa/totp",            to: "users/mfa#verify_totp",     as: :user_mfa_totp
    post   "users/mfa/recovery",        to: "users/mfa#verify_recovery", as: :user_mfa_recovery
    post   "users/mfa/passkey/options", to: "users/mfa#passkey_options", as: :user_mfa_passkey_options
    post   "users/mfa/passkey",         to: "users/mfa#verify_passkey",  as: :user_mfa_passkey
  end
  root to: redirect("/dashboard")

  # エラーページ: /errors?status=404 で個別プレビュー、/errors でコード一覧
  get "/errors", to: "errors#show",  as: :errors,       constraints: ->(req) { req.params[:status].present? }
  get "/errors", to: "errors#index", as: :errors_index
  # exceptions_app 用: Railsが例外を /400, /404 等にルーティングする
  %w[400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418
     421 422 423 424 425 426 428 429 431 451
     500 501 502 503 504 505 506 507 508 510 511].each do |code|
    get "/#{code}", to: "errors#show", defaults: { status: code }
  end

  namespace :dashboard do
    root to: "dashboards#index"
    resources :pos_devices, only: [ :new, :create, :destroy ], path: "pos_devices" do
      patch :update_password, path: "update_password"
    end
    resources :stores, path: "stores" do
      member do
        get  :prices
        patch :update_prices
      end
    end
    resources :employees, except: [ :show ]
    resources :product_categories, except: [ :show ]
    resources :products do
      post :import, on: :collection
    end
    resources :provisionings, only: [ :index, :new, :create, :destroy ]
    resources :sales, only: [ :index ]
    resources :sale_details, only: [ :show ]
    resources :refunds, only: [ :index, :show ]
    resources :cash_logs, only: [ :index ]
    resources :store_stocks, only: [ :index, :update ] do
      post :transfer, on: :collection
    end
    resources :stock_movements, only: [ :index ]
    resources :product_bundles, except: [ :show ]
    resources :reports, only: [ :index ]
    resources :analytics, only: [ :index ]
    # セキュリティ設定（2段階認証の管理）
    get    "security",                   to: "security#show",                      as: :security
    get    "security/totp/new",          to: "security#new_totp",                  as: :new_security_totp
    post   "security/totp",              to: "security#create_totp",               as: :security_totp
    delete "security/totp",              to: "security#destroy_totp"
    post   "security/passkeys/options",  to: "security#passkey_options",           as: :security_passkey_options
    post   "security/passkeys",          to: "security#create_passkey",            as: :security_passkeys
    delete "security/passkeys/:id",      to: "security#destroy_passkey",           as: :security_passkey
    post   "security/recovery_codes",    to: "security#regenerate_recovery_codes", as: :security_recovery_codes
    get    "security/recovery_codes",    to: "security#recovery_codes"
  end

  namespace :api do
    namespace :v1 do
      resources :pos_devices do
        post :login, on: :collection
        post :top_user_login, on: :collection
        post :open, on: :collection
        post :check_operator, on: :collection
        post :verify_employee, on: :collection
        post :provisioning, on: :collection
        get  :cash_check_context, on: :collection
        post :cash_check, on: :collection
        post :close_register, on: :collection
        post :cash_pickup, on: :collection
        get  :register_report, on: :collection
      end
      resources :products do
        post :sync,   on: :collection
        get  :lookup, on: :collection
      end
      resources :sales, only: [ :create, :index ] do
        get :summary, on: :collection
        post :void, on: :member
        post :issue_receipt, on: :member
      end
      resources :store_stocks, only: [ :index ] do
        post :move, on: :collection
      end
      resources :refunds, only: [ :create ] do
        get :sale_by_receipt, on: :collection
      end
      get "store_prices", to: "store_prices#index"
      patch "store_prices", to: "store_prices#update"
      # 飲食店モード用：テーブルごとの注文（店舗内POS共有）
      resources :table_orders, only: [ :index ] do
        collection do
          get  ":table_number", to: "table_orders#show",   as: :show
          put  ":table_number", to: "table_orders#upsert", as: :upsert
          delete ":table_number", to: "table_orders#destroy", as: :destroy
        end
      end
      # 小売店モード用：保留注文（店舗内POS共有）
      resources :hold_orders, only: [ :index, :create, :destroy ]
      # ホスト・クライアントモード用：転送注文（クライアントからホストへのカート転送）
      resources :transfer_orders, only: [ :index, :create, :destroy ]
      # レジ現金の入出金（釣銭補充・雑入出金・途中回収）
      resources :cash_movements, only: [ :index, :create ]
      # 電子ジャーナル（view_journal 権限必須）
      resources :journals, only: [ :index, :show ]
    end
  end
end
