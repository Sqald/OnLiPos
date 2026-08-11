# 店舗在庫の閲覧・入出荷登録API。
class Api::V1::StoreStocksController < Api::V1::BaseController
  # GET /api/v1/store_stocks — 自店舗の在庫一覧（商品名順）
  def index
    store = @current_pos.store

    stocks = store.store_stocks
      .includes(:product)
      .joins(:product)
      .order("products.name")

    render json: {
      success: true,
      stocks: stocks.map { |s|
        {
          product_id: s.product.id,
          product_name: s.product.name,
          product_code: s.product.code,
          quantity: s.quantity
        }
      }
    }
  end

  # 在庫の入出荷をまとめて登録するエンドポイント。
  # POST /api/v1/store_stocks/move
  #
  # リクエスト例:
  # {
  #   "employee_id": 1,
  #   "movements": [
  #     { "jan_code": "4901234567890", "quantity": 5, "direction": "in" },
  #     { "jan_code": "4909876543210", "quantity": 2, "direction": "out" }
  #   ]
  # }
  def move
    movements = params[:movements]
    employee_id = params[:employee_id]

    if movements.blank? || !movements.is_a?(Array)
      render json: { success: false, message: "movements が不正です" }, status: :bad_request
      return
    end

    owner = @current_pos.store.user
    employee = owner.employees.find_by(id: employee_id)

    unless employee && (employee.is_all_stores || employee.stores.exists?(@current_pos.store.id))
      render json: { success: false, message: "担当者が見つからないか、店舗の権限がありません" }, status: :forbidden
      return
    end

    results = []

    # 全件を1トランザクションで処理し、不正なデータが1件でもあれば全体をロールバックする
    ActiveRecord::Base.transaction do
      movements.each do |movement|
        jan_code = movement[:jan_code].presence || movement["jan_code"].presence
        quantity = (movement[:quantity] || movement["quantity"]).to_i
        direction = movement[:direction].presence || movement["direction"].presence

        if jan_code.blank? || quantity <= 0 || !%w[in out].include?(direction)
          raise ActiveRecord::Rollback, "不正な入出荷データです"
        end

        product = owner.products.find_by(code: jan_code)
        unless product
          raise ActiveRecord::Rollback, "JANコードに該当する商品が存在しません: #{jan_code}"
        end

        store = @current_pos.store
        store_stock = StoreStock.find_or_create_by!(store: store, product: product)

        store_stock.with_lock do
          new_quantity =
            if direction == "in"
              store_stock.quantity + quantity
            else
              store_stock.quantity - quantity
            end

          change_value = direction == "in" ? quantity : -quantity

          store_stock.update!(quantity: new_quantity)

          StockMovement.create!(
            store: store,
            product: product,
            store_stock: store_stock,
            employee: employee,
            pos_token: @current_pos,
            quantity_change: change_value,
            reason: direction == "in" ? "manual_in" : "manual_out"
          )

          results << {
            jan_code: jan_code,
            product_name: product.name,
            direction: direction,
            quantity: quantity,
            stock_quantity: store_stock.quantity
          }
        end
      end
    end

    render json: {
      success: true,
      movements: results
    }, status: :ok
  rescue => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  end
end
