# 在庫が不足している商品
class Dashboard::LowStocksController < Dashboard::BaseController
  def index
    @stocks = StoreStock.joins(:product, :store).includes(:store, product: :supplier).where(stores: { user_id: current_account.id })
                        .where("products.low_stock_threshold IS NOT NULL AND store_stocks.quantity <= products.low_stock_threshold AND products.status = 0")
                        .order("stores.name", "products.name").page(params[:page]).per(100)
  end
end
