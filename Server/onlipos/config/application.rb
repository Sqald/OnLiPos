require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Onlipos
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
    config.hosts << "rails:3000"
    config.hosts << ENV['HOST_NAME'] || "localhost"
    config.time_zone = "Tokyo"
    config.i18n.default_locale = :ja

    config.action_mailer.smtp_settings = {
      address:              ENV['SMTP_ADDRESS'],
      domain:               ENV['SMTP_DOMAIN'],
      port:                 ENV['SMTP_PORT'] || 587, # 値がなければ587を使う
      user_name:            ENV['SMTP_USER_NAME'],
      password:             ENV['SMTP_PASSWORD'],
      authentication:       'plain',
      enable_starttls_auto: true
    }

    config.action_mailer.default_url_options = { 
      host: ENV['HOST_NAME'], 
      port: ENV['HOST_PORT'] || 3000 
    }
  end
end
