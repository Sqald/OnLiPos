class Api::V1::TransferOrdersController < Api::V1::BaseController
  # GET /api/v1/transfer_orders
  # ホスト待ち受け用：店舗内の未処理転送注文一覧（アイテム詳細なし）
  def index
    transfers = @current_pos.store.transfer_orders.order(created_at: :asc)
    render json: {
      success: true,
      transfer_orders: transfers.map { |t|
        {
          id:            t.id,
          operator_name: t.operator_name,
          operator_id:   t.operator_id,
          total_amount:  t.total_amount,
          item_count:    t.items.size,
          table_number:  t.table_number,
          created_at:    t.created_at.iso8601
        }
      }
    }
  end

  # POST /api/v1/transfer_orders
  # クライアント機がカート内容をサーバーに転送する
  def create
    transfer = @current_pos.store.transfer_orders.build(transfer_params)
    allowed_keys = %w[product_id product_name product_code quantity unit_price subtotal tax_rate bundle_code]
    transfer.items = (params.dig(:transfer_order, :items) || []).map do |item|
      item.to_h.stringify_keys.slice(*allowed_keys)
    end

    if transfer.save
      render json: { success: true, id: transfer.id }, status: :created
    else
      render json: { success: false, errors: transfer.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/transfer_orders/:id
  # ホスト機が転送注文を受け取る（取得後に削除）
  def destroy
    transfer = @current_pos.store.transfer_orders.find_by(id: params[:id])

    if transfer.nil?
      render json: { success: false, error: '転送注文が見つかりません' }, status: :not_found
      return
    end

    payload = nil
    begin
      transfer.with_lock do
        payload = {
          id:            transfer.id,
          operator_name: transfer.operator_name,
          operator_id:   transfer.operator_id,
          total_amount:  transfer.total_amount,
          table_number:  transfer.table_number,
          items:         transfer.items
        }
        transfer.destroy!
      end
    rescue ActiveRecord::RecordNotFound
      render json: { success: false, error: '転送注文が見つかりません' }, status: :not_found
      return
    end

    render json: { success: true, transfer_order: payload }
  end

  private

  def transfer_params
    params.require(:transfer_order).permit(:operator_name, :operator_id, :total_amount, :table_number)
  end
end
