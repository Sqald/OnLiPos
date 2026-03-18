# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin AJAX requests.

# Read more: https://github.com/cyu/rack-cors

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    if Rails.env.production?
      # 本番環境では環境変数で指定されたオリジンのみを許可
      origins ENV.fetch('CORS_ORIGINS', '').split(',')
    else
      # 開発環境ではすべてのオリジンを許可
      origins '*'
    end

    resource '/api/*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      # トークンやクッキーなどの資格情報をリクエストに含めることを許可
      credentials: false 
  end
end
