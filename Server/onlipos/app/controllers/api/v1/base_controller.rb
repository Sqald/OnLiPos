# api/v1 配下の全コントローラ（Flutter POS端末向けJSON API）の共通基底クラス。
# 全アクションの前に POSトークン認証（Bearer / X-POS-Token ヘッダー）を行い、
# 認証済みの PosToken を @current_pos にセットする。
class Api::V1::BaseController < Api::BaseController
  include EmployeePermissionAuthorizable

  before_action :authenticate_pos_token
  rescue_from ActiveRecord::RecordNotFound,
              with: -> { render json: { success: false, message: "リソースが見つかりません" }, status: :not_found }

  private

  # リクエストから POS トークンを取り出し、有効なら @current_pos にセットする。
  # 無効な場合は 401 を返してリクエストを打ち切る。
  def authenticate_pos_token
    @current_pos = PosToken.find_by_token(pos_token_from_request)
    return render_unauthorized unless @current_pos

    # 停止した端末・利用停止中の契約は、トークンが正しくても使えない
    if @current_pos.disabled?
      return render json: { success: false, code: "terminal_disabled", message: "この端末は管理画面で停止されています" }, status: :unauthorized
    end
    if @current_pos.store.user.suspended?
      return render json: { success: false, code: "account_suspended", message: "ご契約のアカウントは利用停止中です" }, status: :forbidden
    end
    return render_upgrade_required if app_version_outdated?

    record_terminal_usage
    Current.account = @current_pos.store.user
    Current.actor = @current_pos
    Current.ip_address = request.remote_ip
  end

  def render_unauthorized
    render json: { success: false, message: "Unauthorized" }, status: :unauthorized
  end

  # 直近利用時刻の更新は10分に1回程度に間引く（毎リクエストのUPDATEを避ける）
  def record_terminal_usage
    version = request.headers["X-App-Version"].to_s.slice(0, 32).presence
    recently_used = @current_pos.last_used_at && @current_pos.last_used_at > 10.minutes.ago
    return if recently_used && (version.nil? || version == @current_pos.app_version)

    @current_pos.update_columns({
      last_used_at: Time.current, last_ip: request.remote_ip, app_version: version,
      platform: request.headers["X-App-Platform"].to_s.slice(0, 32).presence
    }.compact)
  end

  # MIN_APP_VERSION（例: 1.2.0）より古いアプリを拒否する。未設定なら確認しない
  def app_version_outdated?
    minimum = ENV["MIN_APP_VERSION"].presence
    return false unless minimum

    version = request.headers["X-App-Version"].to_s[/\A\d+(\.\d+){0,3}/]
    version.nil? || Gem::Version.new(version) < Gem::Version.new(minimum)
  end

  def render_upgrade_required
    render json: { success: false, code: "upgrade_required", message: "アプリの更新が必要です（#{ENV['MIN_APP_VERSION']} 以上）" }, status: :upgrade_required
  end

  MAX_CART_ITEMS = 500

  # 端末間で共有するカートの明細（保留・卓・転送）。中身は端末の形式のまま保存するため、
  # 件数と「オブジェクトの配列であること」だけを確認する。金額は会計時にサーバーで検証する
  def cart_items(raw)
    Array(raw).first(MAX_CART_ITEMS).select { |item| item.is_a?(ActionController::Parameters) }.map(&:to_unsafe_h)
  end

  # このPOS端末で現在開いているレジセッション（なければ nil = レガシー動作）
  def current_register_session
    return @current_register_session if defined?(@current_register_session)
    @current_register_session = @current_pos.register_sessions.open.first
  end

  # Authorization: Bearer ヘッダー、または X-POS-Token ヘッダーからトークンを取り出す。
  # URLに含めるとアクセスログに残るため、パラメータでは受け付けない。
  def pos_token_from_request
    auth_header = request.authorization.to_s
    return auth_header.delete_prefix("Bearer ").strip if auth_header.start_with?("Bearer ")

    request.headers["X-POS-Token"].to_s.strip.presence
  end
end
