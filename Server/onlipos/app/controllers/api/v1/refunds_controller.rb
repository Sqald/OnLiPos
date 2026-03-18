# frozen_string_literal: true

class Api::V1::RefundsController < Api::V1::BaseController
  # レシート番号で売上を検索（返品対象の会計を表示する用）。自店舗の売上のみ。
  def sale_by_receipt
    receipt_number = params[:receipt_number].to_s.strip
    if receipt_number.blank?
      render json: { success: false, message: "レシート番号を入力してください" }, status: :ok
      return
    end

    sale = Sale
      .where(store_id: @current_pos.store_id, user_id: @current_pos.store.user_id)
      .includes(:saledetails, :sale_payments)
      .find_by(receipt_number: receipt_number)

    unless sale
      render json: { success: false, message: "該当する会計が見つかりません" }, status: :ok
      return
    end

    details = sale.saledetails.includes(:product).map do |d|
      {
        id: d.id,
        product_id: d.product_id,
        product_name: d.product_name,
        product_code: d.product&.code,
        quantity: d.quantity,
        unit_price: d.unit_price,
        subtotal: d.subtotal
      }
    end

    payments = sale.sale_payments.map do |p|
      # enum の数値コードを返すことでクライアント側の0:現金/1:カード/2:バーコード決済と揃える
      { method: p.method_before_type_cast, amount: p.amount }
    end

    render json: {
      success: true,
      sale: {
        id: sale.id,
        receipt_number: sale.receipt_number,
        total_amount: sale.total_amount,
        created_at: sale.created_at,
        refunded: sale.refunds.exists?
      },
      details: details,
      payments: payments
    }, status: :ok
  end

  # 返品・返金を登録。従業員2名以上の認証必須。一個単位で返品可能。
  def create
    receipt_number = params[:receipt_number].to_s.strip
    employee_ids = Array(params[:employee_ids]).map(&:to_i).uniq
    details_param = params[:details]

    if receipt_number.blank?
      render json: { success: false, message: "レシート番号を指定してください" }, status: :ok
      return
    end

    if employee_ids.size < 2
      render json: { success: false, message: "返品には2名以上の従業員認証が必要です" }, status: :ok
      return
    end

    owner = @current_pos.store.user
    employees = owner.employees.where(id: employee_ids)
    employees = employees.select { |e| e.is_all_stores || e.stores.exists?(@current_pos.store_id) }
    if employees.size < 2
      render json: { success: false, message: "認証された従業員が不足しているか、店舗権限がありません" }, status: :ok
      return
    end

    sale = Sale.where(store_id: @current_pos.store_id, user_id: @current_pos.store.user_id)
               .find_by(receipt_number: receipt_number)
    unless sale
      render json: { success: false, message: "該当する会計が見つかりません" }, status: :ok
      return
    end

    if sale.refunds.exists?
      render json: { success: false, message: "この会計はすでに返品済みです" }, status: :ok
      return
    end

    unless details_param.is_a?(Array) && details_param.any?
      render json: { success: false, message: "返品明細を1件以上指定してください" }, status: :ok
      return
    end

    # 返品明細: saledetail_id と quantity（返品する個数）
    detail_items = details_param.map do |d|
      sid = d[:saledetail_id] || d["saledetail_id"]
      qty = (d[:quantity] || d["quantity"]).to_i
      [sid.to_i, qty]
    end

    detail_items = detail_items.reject { |_sid, qty| qty <= 0 }
    if detail_items.empty?
      render json: { success: false, message: "返品する数量を指定してください" }, status: :ok
      return
    end

    sale_detail_ids = sale.saledetails.pluck(:id)
    saledetails_by_id = sale.saledetails.index_by(&:id)

    refund_details_build = []
    total_refund = 0

    detail_items.each do |saledetail_id, return_qty|
      unless sale_detail_ids.include?(saledetail_id)
        render json: { success: false, message: "無効な明細IDです" }, status: :ok
        return
      end
      sd = saledetails_by_id[saledetail_id]
      if return_qty > sd.quantity
        render json: { success: false, message: "返品数量が販売数量を超えています: #{sd.product_name}" }, status: :ok
        return
      end
      subtotal = sd.unit_price * return_qty
      total_refund += subtotal
      refund_details_build << { saledetail: sd, quantity: return_qty, unit_price: sd.unit_price, subtotal: subtotal }
    end

    refund = nil
    ActiveRecord::Base.transaction do
      refund = Refund.create!(
        sale: sale,
        store: sale.store,
        user: sale.user,
        pos_token: @current_pos,
        total_amount: total_refund
      )

      refund_details_build.each do |row|
        refund.refund_details.create!(
          saledetail: row[:saledetail],
          product_id: row[:saledetail].product_id,
          product_name: row[:saledetail].product_name,
          quantity: row[:quantity],
          unit_price: row[:unit_price],
          subtotal: row[:subtotal]
        )
      end

      # 元会計を「すべて返品」として在庫を全明細分戻す。
      # 未返品分はクライアントで再会計するため、ここで全量戻しておく。
      store = sale.store
      sale.saledetails.each do |sd|
        product = sd.product
        next unless product
        store_stock = StoreStock.find_or_create_by!(store: store, product: product)
        store_stock.with_lock do
          store_stock.increment!(:quantity, sd.quantity)
          StockMovement.create!(
            store: store,
            product: product,
            store_stock: store_stock,
            sale: sale,
            pos_token: @current_pos,
            quantity_change: sd.quantity,
            reason: "return"
          )
        end
      end
    end

    render json: {
      success: true,
      refund_id: refund.id,
      refund_receipt_number: refund.refund_receipt_number,
      total_refund_amount: refund.total_amount
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.message }, status: :ok
  end
end
