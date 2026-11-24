# 厨房画面（トークンを含むURL）。一定間隔で自動更新し、ボタンで「調理中 → 提供済み」に進める
class KitchenDisplaysController < ActionController::Base
  layout "public_page"
  protect_from_forgery with: :exception
  before_action :set_store

  def show
    @orders = @store.kitchen_orders.in_progress.limit(100)
  end

  def advance
    @store.kitchen_orders.find(params[:id]).advance!
    redirect_to kitchen_path(params[:token]), status: :see_other
  end

  private

  def set_store
    @store = Store.includes(:user).find_by(kitchen_display_token: params[:token].to_s.presence || "-")
    head :not_found if @store.nil? || @store.user.suspended?
  end
end
