Rails.application.routes.draw do
  # ヘルスチェック用（config.silence_healthcheck_path / ssl_options の除外設定が /up を前提にしている）
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: [ :confirmations, :unlocks, :passwords, :omniauth_callbacks ], controllers: { sessions: "users/sessions", registrations: "users/registrations" }
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

  # 電子レシート（推測できないURLを知る人だけが見られる）
  get "r/:token", to: "digital_receipts#show", as: :digital_receipt_full

  # お客様のスマートフォンからの注文（卓のQRコード）
  get  "order/:token", to: "self_orders#show",   as: :self_order
  post "order/:token", to: "self_orders#create"
  # 厨房画面・客用表示（トークンを含むURLを知る端末のみ）
  get  "kitchen/:token", to: "kitchen_displays#show", as: :kitchen
  post "kitchen/:token/:id/advance", to: "kitchen_displays#advance", as: :kitchen_advance
  get  "display/:token", to: "customer_displays#show", as: :customer_display_page

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
    resource :help, only: [ :show ], controller: "help"
    resources :pos_devices, only: [ :index, :new, :create, :destroy ], path: "pos_devices" do
      patch :update_password, path: "update_password"
      member do
        patch :disable
        patch :enable
      end
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
      get  :export, on: :collection
      get  :image, on: :member
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
    resources :register_sessions, only: [ :index, :show ]
    resources :journals, only: [ :index, :show ] do
      get :verify, on: :collection
    end
    resources :sale_reviews, only: [ :index, :update ]
    # 商品・販売促進
    resources :option_groups, except: [ :show ]
    resources :scheduled_changes, only: [ :index, :create, :destroy ] do
      collection do
        get :tax_change
        post :apply_tax_change
        delete :destroy_batch
      end
    end
    resources :coupons, except: [ :show ]
    resources :promotions, except: [ :show ]
    resources :customers do
      member do
        post :adjust
        post :anonymize
      end
    end
    # 仕入・棚卸
    resources :suppliers, except: [ :show ]
    resources :purchase_orders do
      member do
        post :place
        post :receive
        post :cancel
      end
    end
    resources :stocktakes, only: [ :index, :create, :show ] do
      member do
        post :count
        post :complete
        post :cancel
      end
    end
    resources :low_stocks, only: [ :index ]
    # 店舗運営
    resources :attendances, only: [ :index, :update ]
    resources :reservations, except: [ :show ]
    resources :table_codes, only: [ :index, :create, :destroy ] do
      post :rotate, on: :member
      patch :settings, on: :collection
    end
    # 外部連携
    resource :accounting_export, only: [ :show ]
    resources :api_keys, only: [ :index, :create, :destroy ]
    resources :webhooks, except: [ :show ]
    # 契約・メンバー・操作履歴
    resource :account_settings, only: [ :show, :update ]
    resources :members, only: [ :index, :new, :create, :update, :destroy ] do
      post :reset_password, on: :member
    end
    resources :audit_logs, only: [ :index ]
    resource :reauthentication, only: [ :new, :create ]
    # セキュリティ設定（2段階認証の管理）
    get    "security",                   to: "security#show",                      as: :security
    get    "security/totp/new",          to: "security#new_totp",                  as: :new_security_totp
    post   "security/totp",              to: "security#create_totp",               as: :security_totp
    delete "security/totp",              to: "security#destroy_totp"
    post   "security/passkeys/options",  to: "security#passkey_options",           as: :security_passkey_options
    post   "security/passkeys",          to: "security#create_passkey",            as: :security_passkeys
    delete "security/passkeys/:id",      to: "security#destroy_passkey",           as: :security_passkey
    post   "security/recovery_codes",    to: "security#regenerate_recovery_codes", as: :security_recovery_codes
    post   "security/sign_out_everywhere", to: "security#sign_out_everywhere",     as: :security_sign_out_everywhere
    get    "security/recovery_codes",    to: "security#recovery_codes"
  end

  namespace :api do
    # 外部連携用API（APIキー認証）
    namespace :external do
      namespace :v1 do
        resources :sales, only: [ :index, :show ]
        resources :refunds, only: [ :index ]
        resources :products, only: [ :index, :show, :create, :update ]
        resources :stocks, only: [ :index ]
        resources :customers, only: [ :index ]
      end
    end
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
        get  :image,  on: :member
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
      # 会員
      resources :customers, only: [ :index, :create ]
      # クーポンの確認
      resources :coupons, only: [ :show ]
      # 勤怠の打刻
      resources :attendances, only: [ :index, :create ]
      # 棚卸の数量登録
      resources :stocktakes, only: [ :index ] do
        post :count, on: :member
      end
      # 入荷
      resources :purchase_orders, only: [ :index, :show ] do
        post :receive, on: :member
      end
      # 予約の確認
      resources :reservations, only: [ :index, :update ]
      # 厨房への注文・客用表示
      resources :kitchen_orders, only: [ :index, :create, :update ]
      resource :customer_display, only: [ :show, :update ]
      # 電子ジャーナル（view_journal 権限必須）
      resources :journals, only: [ :index, :show ]
    end
  end
end
