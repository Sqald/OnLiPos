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

    calculator = RefundCalculator.new(sale)

    details = sale.saledetails.includes(:product).map do |d|
      refundable_qty = calculator.remaining_quantity(d)
      {
        id: d.id,
        product_id: d.product_id,
        product_name: d.product_name,
        product_code: d.product&.code,
        quantity: d.quantity,
        unit_price: d.unit_price,
        subtotal: d.subtotal,
        refunded_quantity: d.quantity - refundable_qty,
        refundable_quantity: refundable_qty,
        # 数量ごとの返金額（1個, 2個, …）。端末はこの額を表示する
        refund_amounts: (1..[ refundable_qty, 200 ].min).map { |q| calculator.line_amount(d, q) }
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
        voided: sale.voided?,
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
    employee_ids = params[:employee_ids]
    details_param = params[:details]

    # 入力チェック: レシート番号必須
    if receipt_number.blank?
      render json: { success: false, message: "レシート番号を指定してください" }, status: :bad_request
      return
    end

    employees = require_dual_approval!(employee_ids, "refund", action_label: "返品")
    return unless employees

    # 対象の売上を特定（自店舗のもののみ）
    sale = Sale.where(store_id: @current_pos.store_id, user_id: @current_pos.store.user_id)
               .includes(saledetails: :product)
               .find_by(receipt_number: receipt_number)
    unless sale
      render json: { success: false, message: "該当する会計が見つかりません" }, status: :not_found
      return
    end

    if sale.voided?
      render json: { success: false, message: "取消済みの会計は返品できません" }, status: :unprocessable_entity
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
    ActiveRecord::Base.transaction do
      # ロック取得後に返品済み数量・取消状態を確認し、同時実行でも二重に返金しないようにする
      sale.lock!
      raise RefundCalculator::Error, "取消済みの会計は返品できません" if sale.voided?

      result = RefundCalculator.new(sale).calculate(
        detail_items.map { |saledetail_id, quantity| [ saledetails_by_id[saledetail_id], quantity ] }
      )
      breakdowns = result.breakdowns

      unless consume_approvals(employees, "refund", "refund:#{sale.receipt_number}")
        raise RefundCalculator::Error, "担当者の認証がすでに使用されています。もう一度認証してください"
      end

      session = current_register_session
      refund = Refund.create!(
        sale: sale,
        store: sale.store,
        user: sale.user,
        pos_token: @current_pos,
        employee: employees.first,
        # 返金額は内訳の税込対価合計（外税明細は税額を加算した額を返金する）
        total_amount: result.total_amount,
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

      result.lines.each do |line|
        refund.refund_details.create!(
          saledetail: line.saledetail,
          product_id: line.saledetail.product_id,
          product_name: line.saledetail.product_name,
          quantity: line.quantity,
          unit_price: line.unit_price,
          subtotal: line.subtotal,
          tax_rate: line.saledetail.tax_rate,
          tax_amount: line.tax_amount
        )
      end

      save_refund_payments(refund, sale)

      # 在庫は返品された明細・数量分だけ戻す（返金額と在庫の対称性を保つ）
      result.lines.each do |line|
        next unless line.saledetail.product

        StoreStock.adjust!(store: sale.store, product: line.saledetail.product, change: line.quantity, reason: "return",
                           employee: employees.first, pos_token: @current_pos, sale: sale)
      end
      Loyalty.apply_refund!(refund)

      JournalEntry.create_from_refund!(refund, refund.refund_details)
    end

    Webhook.publish(sale.user, "refund.created", SalePayload.refund(refund))
    render json: {
      success: true,
      refund_id: refund.id,
      refund_receipt_number: refund.refund_receipt_number,
      total_refund_amount: refund.total_amount,
      payments: refund.refund_payments.map { |p| { method: RefundPayment.defined_enums["method"][p.method], amount: p.amount } }
    }, status: :created
  rescue RefundCalculator::Error => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  end

  private

  # 返金の決済手段別内訳を保存する。
  # 端末から payments が送られればそれを使い（元の会計の支払額を超えないこと）、
  # なければ元の会計の支払比率で按分する（現金以外は残額をまとめて主たる手段に計上）。
  def save_refund_payments(refund, sale)
    return if refund.total_amount.zero?

    paid = sale.sale_payments.group(:method).sum(:amount)
    refunded = RefundPayment.joins(:refund).where(refunds: { sale_id: sale.id }).group(:method).sum(:amount)
    remaining = paid.to_h { |method, amount| [ method, [ amount - refunded.fetch(method, 0), 0 ].max ] }

    requested_refund_payments(refund, remaining) || allocate_refund_payments(refund, remaining, sale)
  end

  def requested_refund_payments(refund, remaining)
    raw = params[:payments]
    return unless raw.is_a?(Array) && raw.any?

    rows = raw.map { |p| p.permit(:method, :amount, :external_reference) }
    unless rows.sum { |p| p[:amount].to_i } == refund.total_amount
      raise RefundCalculator::Error, "返金の内訳の合計が返金額と一致しません"
    end

    rows.group_by { |p| RefundPayment.defined_enums["method"].key(p[:method].to_i) }.each do |method, group|
      # カード等への返金は元の支払額まで。現金での返金は、決済端末で取消できない場合のために上限を設けない
      if method.nil? || (method != "cash" && group.sum { |p| p[:amount].to_i } > remaining.fetch(method, 0))
        raise RefundCalculator::Error, "返金方法または返金額が元の会計の支払いと一致しません"
      end
    end

    rows.each do |p|
      refund.refund_payments.create!(method: p[:method].to_i, amount: p[:amount].to_i,
                                     external_reference: p[:external_reference].presence&.slice(0, 100))
    end
  end

  def allocate_refund_payments(refund, remaining, sale)
    total = remaining.values.sum
    if total.zero?
      refund.refund_payments.create!(method: sale.payment_method_before_type_cast, amount: refund.total_amount)
      return
    end

    methods = remaining.select { |_, amount| amount.positive? }.sort_by { |_, amount| amount }
    left = refund.total_amount
    methods.each_with_index do |(method, amount), index|
      share = index == methods.size - 1 ? left : [ (Rational(refund.total_amount * amount, total)).round, left ].min
      refund.refund_payments.create!(method: method, amount: share) if share.positive?
      left -= share
    end
  end
end
