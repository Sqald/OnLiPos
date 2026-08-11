# frozen_string_literal: true

# 返品・返金APIを扱うコントローラ。
# 元の売上（レシート番号で特定）に対し、明細単位で部分返品できる。
# 不正防止のため従業員2名以上の認証（refund権限）を必須とする。
class Api::V1::RefundsController < Api::V1::BaseController
  # レシート番号で売上を検索（返品対象の会計を表示する用）。自店舗の売上のみ。
  def sale_by_receipt
    receipt_number = params[:receipt_number].to_s.strip
    if receipt_number.blank?
      render json: { success: false, message: "レシート番号を入力してください" }, status: :bad_request
      return
    end

    sale = Sale
      .where(store_id: @current_pos.store_id, user_id: @current_pos.store.user_id)
      .includes(:saledetails, :sale_payments)
      .find_by(receipt_number: receipt_number)

    unless sale
      render json: { success: false, message: "該当する会計が見つかりません" }, status: :not_found
      return
    end

    refunded_by_detail = refunded_quantities(sale)

    details = sale.saledetails.includes(:product).map do |d|
      refunded_qty = refunded_by_detail[d.id] || 0
      {
        id: d.id,
        product_id: d.product_id,
        product_name: d.product_name,
        product_code: d.product&.code,
        quantity: d.quantity,
        unit_price: d.unit_price,
        subtotal: d.subtotal,
        refunded_quantity: refunded_qty,
        refundable_quantity: d.quantity - refunded_qty
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
        # 全明細の数量が返品済みの場合のみ true（部分返品後の残数は返品可能）
        refunded: details.all? { |d| d[:refundable_quantity] <= 0 }
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

    # 入力チェック: レシート番号必須
    if receipt_number.blank?
      render json: { success: false, message: "レシート番号を指定してください" }, status: :bad_request
      return
    end

    if employee_ids.size < 2
      render json: { success: false, message: "返品には2名以上の従業員認証が必要です" }, status: :forbidden
      return
    end

    # 認証された従業員が実在し、店舗権限・返品権限を持つか確認
    owner = @current_pos.store.user
    employees = owner.employees.where(id: employee_ids)
    employees = employees.select { |e| e.is_all_stores || e.stores.exists?(@current_pos.store_id) }
    if employees.size < 2
      render json: { success: false, message: "認証された従業員が不足しているか、店舗権限がありません" }, status: :forbidden
      return
    end

    employees_without_permission = employees.reject { |e| e.permitted?("refund") }
    if employees_without_permission.any?
      names = employees_without_permission.map(&:name).join("、")
      render json: { success: false, message: "返品権限がありません: #{names}" }, status: :forbidden
      return
    end

    # 対象の売上を特定（自店舗のもののみ）
    sale = Sale.where(store_id: @current_pos.store_id, user_id: @current_pos.store.user_id)
               .includes(saledetails: :product)
               .find_by(receipt_number: receipt_number)
    unless sale
      render json: { success: false, message: "該当する会計が見つかりません" }, status: :not_found
      return
    end

    unless details_param.is_a?(Array) && details_param.any?
      render json: { success: false, message: "返品明細を1件以上指定してください" }, status: :bad_request
      return
    end

    # 返品明細: saledetail_id と quantity（返品する個数）
    detail_items = details_param.map do |d|
      sid = d[:saledetail_id] || d["saledetail_id"]
      qty = (d[:quantity] || d["quantity"]).to_i
      [ sid.to_i, qty ]
    end

    detail_items = detail_items.reject { |_sid, qty| qty <= 0 }
    if detail_items.empty?
      render json: { success: false, message: "返品する数量を指定してください" }, status: :bad_request
      return
    end

    saledetails_by_id = sale.saledetails.index_by(&:id)
    sale_detail_ids   = saledetails_by_id.keys

    if detail_items.any? { |saledetail_id, _qty| !sale_detail_ids.include?(saledetail_id) }
      render json: { success: false, message: "無効な明細IDです" }, status: :unprocessable_entity
      return
    end

    # 返品明細の妥当性確認・返金額計算・返品レコード作成・在庫戻しを1トランザクションで行う
    refund = nil
    error_message = nil
    ActiveRecord::Base.transaction do
      sale.lock!

      # 返品済み数量はロック取得後に集計し、同時実行でも残数を超えないようにする
      refunded_by_detail = refunded_quantities(sale)

      calculator = TaxCalculator.new(sale.user.tax_rounding_method)
      refund_details_build = []

      detail_items.each do |saledetail_id, return_qty|
        sd = saledetails_by_id[saledetail_id]
        remaining = sd.quantity - (refunded_by_detail[sd.id] || 0)
        if return_qty > remaining
          error_message = "返品数量が返品可能数量(#{remaining})を超えています: #{sd.product_name}"
          raise ActiveRecord::Rollback
        end

        subtotal = sd.unit_price * return_qty
        # 販売時点の税率・税区分で明細行の税額を計算する（確定値は内訳側で保持）
        tax_amount = calculator.line_tax(subtotal, sd.tax_rate, sd.tax_type)

        refund_details_build << {
          saledetail: sd, quantity: return_qty, unit_price: sd.unit_price,
          subtotal: subtotal, tax_rate: sd.tax_rate, tax_amount: tax_amount
        }
      end

      # 税率別内訳（返還インボイスの記載事項）。売上と同じく税率ごとに端数処理1回
      breakdown_lines = refund_details_build.map do |row|
        { amount: row[:subtotal], tax_rate: row[:tax_rate], tax_type: row[:saledetail].tax_type }
      end
      breakdowns = calculator.breakdowns(breakdown_lines)

      session = @current_pos.register_sessions.open.first
      refund = Refund.create!(
        sale: sale,
        store: sale.store,
        user: sale.user,
        pos_token: @current_pos,
        employee: employees.first,
        # 返金額は内訳の税込対価合計（外税明細は税額を加算した額を返金する）
        total_amount: breakdowns.sum(&:taxable_amount),
        subtotal_ex_tax: breakdowns.sum(&:amount_ex_tax),
        tax_amount: breakdowns.sum(&:tax_amount),
        register_session: session,
        refunded_at: Time.current,
        business_date: session&.business_date || Date.current
      )

      breakdowns.each do |b|
        refund.refund_tax_breakdowns.create!(
          tax_rate: b.tax_rate,
          tax_type: b.tax_type,
          taxable_amount: b.taxable_amount,
          amount_ex_tax: b.amount_ex_tax,
          tax_amount: b.tax_amount
        )
      end

      refund_details_build.each do |row|
        refund.refund_details.create!(
          saledetail: row[:saledetail],
          product_id: row[:saledetail].product_id,
          product_name: row[:saledetail].product_name,
          quantity: row[:quantity],
          unit_price: row[:unit_price],
          subtotal: row[:subtotal],
          tax_rate: row[:tax_rate],
          tax_amount: row[:tax_amount]
        )
      end

      # 在庫は返品された明細・数量分だけ戻す（返金額と在庫の対称性を保つ）
      store = sale.store
      refund_employee = employees.first
      refund_details_build.each do |row|
        product = row[:saledetail].product
        next unless product
        store_stock = StoreStock.find_or_create_by!(store: store, product: product)
        store_stock.with_lock do
          store_stock.increment!(:quantity, row[:quantity])
          StockMovement.create!(
            store: store,
            product: product,
            store_stock: store_stock,
            sale: sale,
            pos_token: @current_pos,
            employee: refund_employee,
            quantity_change: row[:quantity],
            reason: "return"
          )
        end
      end

      JournalEntry.create_from_refund!(refund, refund.refund_details)
    end

    if error_message
      render json: { success: false, message: error_message }, status: :unprocessable_entity
      return
    end

    render json: {
      success: true,
      refund_id: refund.id,
      refund_receipt_number: refund.refund_receipt_number,
      total_refund_amount: refund.total_amount
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  end

  private

  # 売上明細ごとの返品済み数量（saledetail_id => 数量）
  def refunded_quantities(sale)
    RefundDetail.joins(:refund)
                .where(refunds: { sale_id: sale.id })
                .group(:saledetail_id)
                .sum(:quantity)
  end
end
