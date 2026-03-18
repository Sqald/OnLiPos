Rails.application.routes.draw do
  devise_for :users
  root to: "pages#index"
  get "/terms", to: "pages#terms_of_service"

  namespace :dashboard do
    root to: "dashboards#index"
    resources :pos_devices, only: [:new,:create], path: "pos_devices" do
      patch :update_password, path: "update_password"
    end
    resources :stores, path: "stores"
    resources :employees, except: [:show]
    resources :products do
      post :import, on: :collection
    end
    resources :provisionings, only: [:index, :new, :create, :destroy]
    resources :sales, only: [:index]
    resources :sale_details, only: [:show]
    resources :cash_logs, only: [:index]
    resources :store_stocks, only: [:index, :update]
    resources :stock_movements, only: [:index]
  end

  namespace :api do
    namespace :v1 do
      resources :pos_devices do
        post :login, on: :collection
        post :top_user_login, on: :collection
        post :open, on: :collection
        post :check_operator, on: :collection
        post :provisioning, on: :collection
        get  :cash_check_context, on: :collection
        post :cash_check, on: :collection
        post :close_register, on: :collection
      end
      resources :products do
        post :sync, on: :collection
      end
      resources :sales, only: [:create]
      resources :store_stocks, only: [] do
        post :move, on: :collection
      end
      resources :refunds, only: [:create] do
        get :sale_by_receipt, on: :collection
      end
    end
  end
end
