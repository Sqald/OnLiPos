class Api::V1::HoldOrdersController < Api::V1::BaseController
  # GET /api/v1/hold_orders
  # この店舗の保留一覧を返す
  def index
    hold_orders = @current_pos.store.hold_orders.order(created_at: :asc)
    render json: hold_orders.map { |ho|
      {
        hold_number: ho.id,
        operator_name: ho.operator_name,
        operator_id: ho.operator_id,
        total_amount: ho.total_amount,
        items_count: ho.items.length,
        created_at: ho.created_at
      }
    }
  end

  # POST /api/v1/hold_orders
  # 新規保留を作成し、保留番号（id）を返す
  def create
    hold_order = @current_pos.store.hold_orders.new(
      operator_name: hold_params[:operator_name],
      operator_id: hold_params[:operator_id],
      total_amount: hold_params[:total_amount],
      items: hold_params[:items] || []
    )
    if hold_order.save
      render json: { success: true, hold_number: hold_order.id }, status: :created
    else
      render json: { success: false, message: hold_order.errors.full_messages.join(', ') },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/hold_orders/:id
  # 保留を取り出し（削除）、アイテムを返す
  def destroy
    hold_order = @current_pos.store.hold_orders.find_by(id: params[:id])
    unless hold_order
      return render json: { success: false, message: '保留が見つかりません' }, status: :not_found
    end

    data = {
      success: true,
      hold_number: hold_order.id,
      operator_name: hold_order.operator_name,
      operator_id: hold_order.operator_id,
      total_amount: hold_order.total_amount,
      items: hold_order.items
    }
    hold_order.destroy
    render json: data
  end

  private

  def hold_params
    params.permit(:operator_name, :operator_id, :total_amount, items: [{}])
  end
end
