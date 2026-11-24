# 棚卸の数量登録（inventory 権限）
class Api::V1::StocktakesController < Api::V1::BaseController
  def index
    stocktakes = Stocktake.counting.where(store_id: @current_pos.store_id).order(id: :desc)
    render json: { success: true, stocktakes: stocktakes.map { |s| { id: s.id, name: s.name, items_count: s.items.count } } }
  end

  def count
    employee = require_store_employee!(params[:employee_id])
    return unless employee
    authorize_employee!(employee, "inventory")
    return if performed?

    stocktake = Stocktake.where(store_id: @current_pos.store_id).find(params[:id])
    product = @current_pos.store.user.products.find_by(code: params[:jan_code].to_s.strip)
    return render json: { success: false, message: "商品が見つかりません" }, status: :not_found unless product
    unless params[:quantity].to_s.match?(/\A\d{1,7}\z/)
      return render json: { success: false, message: "数量が不正です" }, status: :unprocessable_entity
    end

    item = stocktake.count!(product, params[:quantity].to_i, employee: employee, add: ActiveModel::Type::Boolean.new.cast(params[:add]) || false)
    render json: { success: true, product_name: product.name, counted_quantity: item.counted_quantity }
  rescue Stocktake::Error => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  end
end
