# ダッシュボード用レイアウト（サイドメニュー・上部バー）の表示に必要な、契約アカウントと役割の参照。
# Dashboard::BaseController と、同じレイアウトを使うマイページ（Users::RegistrationsController）で共有する。
module DashboardAccess
  extend ActiveSupport::Concern

  ROLE_LEVELS = { "viewer" => 0, "manager" => 1, "owner" => 2 }.freeze
  ROLE_LABELS = { "owner" => "契約者", "manager" => "管理者（店舗運営全般）", "viewer" => "閲覧のみ" }.freeze

  included do
    helper_method :current_account, :role_at_least?, :role_label, :dashboard_role_label
  end

  private

  # 操作対象の契約アカウント（メンバーの場合は契約者本体）
  def current_account
    @current_account ||= current_user.account
  end

  def role_at_least?(role)
    ROLE_LEVELS.fetch(current_user.role) >= ROLE_LEVELS.fetch(role.to_s)
  end

  def role_label(role) = ROLE_LABELS.fetch(role.to_s, role)
  def dashboard_role_label = role_label(current_user.role)
end
