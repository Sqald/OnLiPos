# api/v1 配下の全コントローラ（Flutter POS端末向けJSON API）の共通基底クラス。
# 全アクションの前に POSトークン認証（Bearer/X-POS-Token/Tokenパラメータ）を行い、
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
    token = pos_token_from_request
    @current_pos = PosToken.find_by(token: token)

    if @current_pos
      # 直近利用時刻の更新は10分に1回程度に間引く（毎リクエストのUPDATEを避ける）
      if @current_pos.last_used_at.nil? || @current_pos.last_used_at < 10.minute.ago
        @current_pos.update_column(:last_used_at, Time.current)
      end
    else
      render json: { success: false, message: "Unauthorized" }, status: :unauthorized
    end
  end

  def auth_params
    params.permit(:Token)
  end

  # Authorization: Bearer ヘッダー、X-POS-Token ヘッダー、Token パラメータの順で
  # トークン文字列を探す（クライアントの実装差異を吸収するため複数経路をサポート）。
  def pos_token_from_request
    auth_header = request.authorization.to_s
    if auth_header.start_with?("Bearer ")
      return auth_header.delete_prefix("Bearer ").strip
    end

    header_token = request.headers["X-POS-Token"].to_s.strip
    return header_token if header_token.present?

    auth_params[:Token]
  end
end
