class Api::V1::BaseController < Api::BaseController
  before_action :authenticate_pos_token

  private

  def authenticate_pos_token
    token = pos_token_from_request
    @current_pos = PosToken.find_by(token: token)

    if @current_pos
      if @current_pos.last_used_at.nil? || @current_pos.last_used_at < 10.minute.ago
        @current_pos.update_column(:last_used_at, Time.current)
      end
    else
      render json: { success: false, message: 'Unauthorized' }, status: :unauthorized
    end
  end

  def auth_params
    params.permit(:Token)
  end

  def pos_token_from_request
    auth_header = request.authorization.to_s
    if auth_header.start_with?('Bearer ')
      return auth_header.delete_prefix('Bearer ').strip
    end

    header_token = request.headers['X-POS-Token'].to_s.strip
    return header_token if header_token.present?

    auth_params[:Token]
  end
end