ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

# ダッシュボードは2段階認証（MFA）を通過したログインのみ有効（MfaSignIn#enforce_mfa_session）。
# Devise のテスト用 sign_in はログイン画面を経由しないため、MFA 通過済みの印も一緒に付ける。
module MfaPassedSignIn
  def sign_in(resource, scope: nil)
    super
    scope ||= Devise::Mapping.find_scope!(resource)
    Warden.on_next_request do |proxy|
      proxy.session(scope)[MfaSignIn::SESSION_MARK] = true if proxy.authenticated?(scope)
    end
  end
end
Devise::Test::IntegrationHelpers.prepend(MfaPassedSignIn)
