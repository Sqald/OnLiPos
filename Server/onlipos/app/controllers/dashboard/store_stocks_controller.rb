class Dashboard::StoreStocksController < Dashboard::BaseController
  before_action :set_store_stock, only: [:update]

  # 店舗在庫一覧画面。
  # 初期表示時は一覧を出さず、JANコードで検索された場合のみ表示する。
  def index
    @jan_code = params[:jan_code].to_s.strip
    @product = nil
    @store_stocks = []

    return if @jan_code.blank?

    @product = current_user.products.find_by(code: @jan_code)
    return unless @product

    @store_stocks = StoreStock
      .includes(:store)
      .where(store: current_user.stores, product: @product)
      .order("stores.name ASC")
  end

  # 一覧から店舗ごとの在庫数量を直接更新する。
  def update
    quantity = params[:store_stock].try(:[], :quantity)

    if quantity.nil?
      redirect_back fallback_location: dashboard_store_stocks_path, alert: "数量を入力してください。"
      return
    end

    if @store_stock.update(quantity: quantity)
      redirect_back fallback_location: dashboard_store_stocks_path(jan_code: params[:jan_code]), notice: "在庫数量を更新しました。"
    else
      redirect_back fallback_location: dashboard_store_stocks_path(jan_code: params[:jan_code]), alert: @store_stock.errors.full_messages.join(", ")
    end
  end

  private

  def set_store_stock
    @store_stock = StoreStock
      .joins(:store)
      .where(stores: { user_id: current_user.id })
      .find(params[:id])
  end
end

