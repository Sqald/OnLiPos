class Api::External::V1::StocksController < Api::External::V1::BaseController
  before_action { require_scope!("stocks:read") }

  def index
    scope = StoreStock.joins(:store).where(stores: { user_id: account.id }).includes(:product)
    scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
    page = paginate(scope)
    render json: { stocks: page[:records].map { |s| { id: s.id, store_id: s.store_id, product_id: s.product_id, product_code: s.product.code, quantity: s.quantity } }, next_after_id: page[:next_after_id] }
  end
end
