# Web ダッシュボード配下の全コントローラの基底クラス。
# Devise によるセッション認証を必須化し、メンバーの役割（role）による操作制限と、
# レコード未検出時の共通ハンドリングを提供する。
class Dashboard::BaseController < ApplicationController
  include DashboardAccess

  layout "dashboard"

  # 参照・変更それぞれに必要な役割。コントローラごとに requires_role で上書きする
  class_attribute :read_role, default: "viewer"
  class_attribute :write_role, default: "manager"

  before_action :authenticate_user!
  before_action :set_current_context
  before_action :enforce_role
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  helper_method :can_write?

  def self.requires_role(read: read_role, write: write_role)
    self.read_role = read
    self.write_role = write
  end

  private

  def can_write? = role_at_least?(write_role)

  def set_current_context
    Current.account = current_account
    Current.actor = current_user
    Current.ip_address = request.remote_ip
  end

  def enforce_role
    required = request.get? || request.head? ? read_role : write_role
    return if role_at_least?(required)

    respond_to do |format|
      format.json { render json: { error: "この操作の権限がありません" }, status: :forbidden }
      format.any { redirect_to dashboard_root_path, alert: "この操作の権限がありません。", status: :see_other }
    end
  end

  # セキュリティに関わる操作の前に、直近のパスワード再入力を求める
  REAUTH_TTL = 10.minutes

  def require_recent_authentication
    return if session[:reauthenticated_at].to_i > REAUTH_TTL.ago.to_i

    session[:reauth_return_to] = request.get? || request.head? ? request.fullpath : dashboard_security_path
    respond_to do |format|
      format.json { render json: { error: "パスワードの再入力が必要です。", redirect: new_dashboard_reauthentication_path }, status: :unauthorized }
      format.any { redirect_to new_dashboard_reauthentication_path, alert: "安全のため、パスワードを再入力してください。", status: :see_other }
    end
  end

  # 検索条件が無いときの初期表示の期間。一覧を開いてすぐ中身が見えるようにする
  def default_period(from, to = Date.current)
    params[:from] = from.to_s
    params[:to] = to.to_s
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  # 対象レコードが見つからない場合はダッシュボードトップへ戻す
  def record_not_found
    redirect_to dashboard_root_path, alert: "指定されたリソースが見つかりません。"
  end
end
