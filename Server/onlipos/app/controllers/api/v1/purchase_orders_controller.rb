# 入荷の登録（inventory 権限）
class Api::V1::PurchaseOrdersController < Api::V1::BaseController
  def index
    orders = receivable.includes(:supplier, :items).order(:expected_on, :id)
    render json: { success: true, purchase_orders: orders.map { |o| { id: o.id, number: o.number, supplier_name: o.supplier.name, expected_on: o.expected_on, items_count: o.items.size } } }
  end

  def show
    order = receivable.find(params[:id])
    render json: { success: true, purchase_order: {
      id: order.id, number: order.number, supplier_name: order.supplier.name,
      items: order.items.includes(:product).map { |i| { id: i.id, product_code: i.product.code, product_name: i.product.name, quantity: i.quantity, received_quantity: i.received_quantity, remaining: i.remaining } }
    } }
  end

  def receive
    employee = require_store_employee!(params[:employee_id])
    return unless employee
    authorize_employee!(employee, "inventory")
    return if performed?

    order = receivable.find(params[:id])
    received = params[:received].respond_to?(:to_unsafe_h) ? params[:received].to_unsafe_h : {}
    order.receive!(received, employee: employee, pos_token: @current_pos)
    render json: { success: true, status: order.status }
  rescue PurchaseOrder::Error => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  end

  private

  def receivable = PurchaseOrder.where(store_id: @current_pos.store_id, status: %i[ordered partially_received])
end
