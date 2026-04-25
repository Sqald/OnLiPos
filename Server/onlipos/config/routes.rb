Rails.application.routes.draw do
  devise_for :users, skip: [:confirmations, :unlocks, :passwords, :omniauth_callbacks]
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
    resources :pos_devices, only: [:new, :create, :destroy], path: "pos_devices" do
      patch :update_password, path: "update_password"
    end
    resources :stores, path: "stores" do
      member do
        get  :prices
        patch :update_prices
      end
    end
    resources :employees, except: [:show]
    resources :products do
      post :import, on: :collection
    end
    resources :provisionings, only: [:index, :new, :create, :destroy]
    resources :sales, only: [:index]
    resources :sale_details, only: [:show]
    resources :cash_logs, only: [:index]
    resources :store_stocks, only: [:index, :update] do
      post :transfer, on: :collection
    end
    resources :stock_movements, only: [:index]
    resources :product_bundles, except: [:show]
    resources :reports, only: [:index]
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
      end
      resources :products do
        post :sync,   on: :collection
        get  :lookup, on: :collection
      end
      resources :sales, only: [:create]
      resources :store_stocks, only: [] do
        post :move, on: :collection
      end
      resources :refunds, only: [:create] do
        get :sale_by_receipt, on: :collection
      end
      # 飲食店モード用：テーブルごとの注文（店舗内POS共有）
      resources :table_orders, only: [:index] do
        collection do
          get  ':table_number', to: 'table_orders#show',   as: :show
          put  ':table_number', to: 'table_orders#upsert', as: :upsert
          delete ':table_number', to: 'table_orders#destroy', as: :destroy
        end
      end
      # 小売店モード用：保留注文（店舗内POS共有）
      resources :hold_orders, only: [:index, :create, :destroy]
      # ホスト・クライアントモード用：転送注文（クライアントからホストへのカート転送）
      resources :transfer_orders, only: [:index, :create, :destroy]
    end
  end
end
