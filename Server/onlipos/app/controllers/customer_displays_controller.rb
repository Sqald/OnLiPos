# 客用表示（トークンを含むURL）。レジのカート内容を一定間隔で更新して表示する
class CustomerDisplaysController < ActionController::Base
  layout "public_page"

  def show
    @display = CustomerDisplay.find_by(token: params[:token].to_s)
    return head :not_found unless @display

    @content = @display.content
    @fresh = @display.updated_at > 30.minutes.ago
    @store = @display.pos_token.store
  end
end
