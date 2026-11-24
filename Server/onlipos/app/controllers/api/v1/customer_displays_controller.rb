# 客用表示の内容を更新する
class Api::V1::CustomerDisplaysController < Api::V1::BaseController
  # 表示用のURLを返す（なければ作成する）
  def show
    display = CustomerDisplay.find_or_create_by!(pos_token: @current_pos)
    render json: { success: true, url: customer_display_page_url(display.token) }
  end

  def update
    items = Array(params[:items]).last(30).select { |i| i.is_a?(ActionController::Parameters) }.map { |i| i.permit(:name, :quantity, :subtotal).to_h }
    display = CustomerDisplay.find_or_create_by!(pos_token: @current_pos)
    display.update!(content: { items: items, total: params[:total].to_i, message: params[:message].to_s.slice(0, 100) }, updated_at: Time.current)
    render json: { success: true }
  end
end
