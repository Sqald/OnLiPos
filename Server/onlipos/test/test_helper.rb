ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # 並列実行用のDBは schema.rb から作られるため、ジャーナル保護トリガーを作成する
    parallelize_setup { JournalProtection.install! }
    JournalProtection.install!

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

# 操作APIはPIN認証で発行された承認トークンの提示が必須（EmployeePermissionAuthorizable）。
# 承認そのものを検証しないテストでは、リクエストの employee_id(s) の承認を自動で添付する。
# 承認を検証するテストでは AutoOperatorApproval.enabled = false にする。
module AutoOperatorApproval
  mattr_accessor :enabled, default: true

  def process(method, path, params: nil, headers: nil, **options)
    if AutoOperatorApproval.enabled && path.to_s.include?("/api/v1/")
      headers = (headers || {}).dup
      bearer = headers["Authorization"].to_s.delete_prefix("Bearer ")
      pos = bearer.present? ? PosToken.find_by_token(bearer) : nil
      if pos && !headers.key?("X-Operator-Approval")
        values = params.is_a?(Hash) ? params.with_indifferent_access : {}
        ids = [ values[:employee_id], *Array(values[:employee_ids]) ].compact
        ids = pos.store.user.employees.ids if ids.empty?
        tokens = Employee.where(id: ids).flat_map do |employee|
          employee.permission_keys.map { |key| OperatorApproval.issue!(employee: employee, pos_token: pos, permission: key).last }
        end
        headers["X-Operator-Approval"] = tokens.join(",") if tokens.any?
      end
    end
    super(method, path, params: params, headers: headers, **options)
  end
end
ActionDispatch::Integration::Session.prepend(AutoOperatorApproval)
