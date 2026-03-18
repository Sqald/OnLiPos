class Dashboard::DashboardsController < Dashboard::BaseController
  def index
    @stores = current_user.stores.includes(:pos_tokens)
    @all_pos_tokens = @stores.map(&:pos_tokens).flatten
  end
end
