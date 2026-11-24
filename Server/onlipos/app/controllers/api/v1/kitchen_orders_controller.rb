# 厨房への注文（レジからの送信・提供済みの処理）
class Api::V1::KitchenOrdersController < Api::V1::BaseController
  def index
    orders = @current_pos.store.kitchen_orders.in_progress.limit(200)
    render json: { success: true, kitchen_orders: orders.map { |o| order_json(o) } }
  end

  def create
    request_id = params[:client_request_id].to_s[/\A[0-9A-Za-z-]{8,64}\z/]
    existing = request_id && @current_pos.store.kitchen_orders.find_by(client_request_id: request_id)
    return render json: { success: true, kitchen_order: order_json(existing) } if existing

    items = Array(params[:items]).first(100).select { |i| i.is_a?(ActionController::Parameters) }.map do |item|
      item.permit(:product_id, :name, :quantity, :note, options: []).to_h
    end
    order = @current_pos.store.kitchen_orders.build(table_number: params[:table_number].to_s.slice(0, 16).presence, items: items, client_request_id: request_id)
    if order.save
      render json: { success: true, kitchen_order: order_json(order) }, status: :created
    else
      render json: { success: false, message: order.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def update
    order = @current_pos.store.kitchen_orders.find(params[:id])
    case params[:event]
    when "advance" then order.advance!
    when "cancel" then order.update!(status: :canceled)
    else return render json: { success: false, message: "操作が不正です" }, status: :unprocessable_entity
    end
    render json: { success: true, kitchen_order: order_json(order) }
  end

  private

  def order_json(order)
    { id: order.id, table_number: order.table_number, source: order.source, status: order.status, status_label: KitchenOrder::STATUS_LABELS[order.status],
      items: order.items, created_at: order.created_at }
  end
end
