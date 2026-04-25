class Api::V1::TableOrdersController < Api::V1::BaseController
  # GET /api/v1/table_orders
  # アクティブな（アイテムがある）テーブル一覧を返す
  def index
    table_orders = @current_pos.store.table_orders.where("jsonb_array_length(items) > 0")
    render json: table_orders.map { |to|
      { table_number: to.table_number, items_count: to.items.length, updated_at: to.updated_at }
    }
  end

  # GET /api/v1/table_orders/:table_number
  # 指定テーブルのアイテムを返す（存在しなければ空配列）
  def show
    table_order = @current_pos.store.table_orders.find_by(table_number: params[:table_number])
    render json: {
      success: true,
      table_number: params[:table_number],
      items: table_order&.items || []
    }
  end

  # PUT /api/v1/table_orders/:table_number
  # 指定テーブルのアイテムを保存（upsert）
  def upsert
    table_order = @current_pos.store.table_orders
                               .find_or_initialize_by(table_number: params[:table_number])
    table_order.items = params[:items] || []
    if table_order.save
      render json: { success: true }
    else
      render json: { success: false, message: table_order.errors.full_messages.join(', ') },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/table_orders/:table_number
  # 指定テーブルのデータを削除（会計完了・全消去時）
  def destroy
    table_order = @current_pos.store.table_orders.find_by(table_number: params[:table_number])
    table_order&.destroy
    render json: { success: true }
  end

  private

  def upsert_params
    params.permit(items: [{}])
  end
end
