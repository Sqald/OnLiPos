# 売上（会計）に関するAPI。会計の登録（create）に加え、日次一覧、期間集計、
# 取消（void）、領収書発行の記録を扱う。
class Api::V1::SalesController < Api::V1::BaseController
  # GET /api/v1/sales?date=YYYY-MM-DD — 指定日（省略時は当日）の自店舗の売上一覧
  def index
    date = params[:date].present? ? Date.parse(params[:date]) : Date.current
    store = @current_pos.store

    sales = store.sales
      .includes(:employee, :sale_payments)
      .where(created_at: date.all_day)
      .order(created_at: :desc)

    render json: {
      success: true,
      date: date.to_s,
      total_amount: sales.sum(:total_amount),
      count: sales.count,
      sales: sales.map { |s|
        {
          id: s.id,
          receipt_number: s.receipt_number,
          total_amount: s.total_amount,
          payment_method: s.payment_method,
          employee_name: s.employee&.name.presence || s.employee&.code,
          created_at: s.created_at.strftime("%H:%M")
        }
      }
    }
  rescue ArgumentError
    render json: { success: false, message: "日付の形式が不正です" }, status: :bad_request
  end

  # GET /api/v1/sales/summary?from=YYYY-MM-DD&to=YYYY-MM-DD&employee_id=...
  def summary
    store    = @current_pos.store
    employee = resolve_employee(store)
    return unless employee

    authorize_employee!(employee, "view_sales")
    return if performed?

    from_date = params[:from].present? ? Date.parse(params[:from]) : Date.current
    to_date   = params[:to].present? ? Date.parse(params[:to]) : Date.current
    range     = from_date..to_date

    # 集計は営業日（business_date）基準・取消（VOID）除外
    sales       = store.sales.completed.where(business_date: range)
    voided      = store.sales.voided.where(business_date: range)
    sale_ids    = sales.select(:id)

    payments_scope = SalePayment.where(sale_id: sale_ids)
    payment_breakdown = {
      cash:    payments_scope.cash.sum(:amount),
      card:    payments_scope.card.sum(:amount),
      barcode: payments_scope.barcode.sum(:amount),
      emoney:  payments_scope.emoney.sum(:amount)
    }

    refunds_scope = Refund.where(store: store, business_date: range)

    daily = sales
      .group(:business_date)
      .select(Arel.sql("business_date AS sale_date, COUNT(*) AS sale_count, SUM(total_amount) AS day_amount"))
      .order(:business_date)

    top_products = Saledetail
      .joins(:sale)
      .where(sales: { store_id: store.id, business_date: range, status: Sale.statuses[:completed] })
      .group(:product_name)
      .select(Arel.sql("product_name, SUM(quantity) AS total_qty, SUM(saledetails.subtotal) AS total_amount"))
      .order(Arel.sql("SUM(saledetails.subtotal) DESC"))
      .limit(20)

    tax_breakdown = TaxSummary.build(sales, refunds_scope).map do |row|
      {
        tax_rate:      row.tax_rate,
        sales_amount:  row.sales_amount,
        sales_tax:     row.sales_tax,
        refund_amount: row.refund_amount,
        refund_tax:    row.refund_tax,
        net_amount:    row.net_amount,
        net_tax:       row.net_tax
      }
    end

    render json: {
      success:           true,
      period:            { from: from_date.to_s, to: to_date.to_s },
      sales_count:       sales.count,
      total_amount:      sales.sum(:total_amount),
      payment_breakdown: payment_breakdown,
      refund_count:      refunds_scope.count,
      refund_total:      refunds_scope.sum(:total_amount),
      void_count:        voided.count,
      void_total:        voided.sum(:total_amount),
      tax_breakdown:     tax_breakdown,
      daily:             daily.map { |d| { date: d.sale_date.to_s, count: d.sale_count.to_i, amount: d.day_amount.to_i } },
      top_products:      top_products.map { |p| { product_name: p.product_name, quantity: p.total_qty.to_i, amount: p.total_amount.to_i } }
    }
  rescue ArgumentError
    render json: { success: false, message: "日付の形式が不正です" }, status: :bad_request
  end

  # POST /api/v1/sales — 会計（売上）を登録する。
  # Sale作成 → 明細保存 → 小計割引適用 → 支払い保存 → 税率別内訳確定、の順で処理し、
  # 失敗時はロールバックしてエラーを返す。
  def create
    # BaseControllerのauthenticate_pos_tokenでセットされた @current_pos を使用
    payments = payment_params_array

    @sale = build_sale(payments)
    @sale.pos_token = @current_pos
    @sale.store = @current_pos.store
    @sale.user = @current_pos.store.user
    @sale.employee = operator_employee

    # レジセッション・営業日・販売時刻の紐付け。
    # sold_at はオフライン会計の後送時にクライアントの計上時刻を受け取る（なければ受信時刻）
    session = current_register_session
    @sale.register_session = session
    @sale.sold_at = client_sold_at || Time.current
    @sale.business_date = session&.business_date || Date.current

    ActiveRecord::Base.transaction do
      if @sale.save
        save_sale_details
        apply_order_discount
        save_sale_payments(payments)
        save_tax_breakdowns

        # Saleモデルのコールバックで pos_token.next_receipt_sequence がインクリメントされているため、
        # 最新の状態をリロードして取得し、クライアントへ返す（オフライン会計用）
        next_sequence = @current_pos.reload.next_receipt_sequence
        # 割引合計を明細から集計してヘッダーに反映
        @sale.update_columns(total_discount: @sale.saledetails.sum(:discount_amount))

        JournalEntry.create_from_sale!(@sale, @sale.saledetails, payments)

        render json: {
          success: true,
          sale_id: @sale.id,
          receipt_number: @sale.receipt_number,
          next_receipt_sequence: next_sequence
        }, status: :created
      else
        render json: { success: false, errors: @sale.errors.full_messages }, status: :unprocessable_entity
        raise ActiveRecord::Rollback
      end
    end
  rescue ArgumentError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  rescue => e
    logger.error "💥 エラー発生: #{e.class} - #{e.message}"
    logger.error e.backtrace.take(5).join("\n") unless Rails.env.production?
    render json: { success: false, errors: [ "Internal Server Error" ] }, status: :internal_server_error
  end

  # POST /api/v1/sales/:id/void — 確定後取消（VOID）
  # 誤登録の訂正用。返品（商品が戻ってきた事実の記録）とは区別し、
  # 締め（精算）前の売上のみ、返品と同じ二重承認で取消できる。
  def void
    sale = Sale.where(store_id: @current_pos.store_id, user_id: @current_pos.store.user_id)
               .includes(saledetails: :product)
               .find_by(id: params[:id])
    unless sale
      return render json: { success: false, message: "該当する会計が見つかりません" }, status: :not_found
    end

    employee_ids = Array(params[:employee_ids]).map(&:to_i).uniq
    if employee_ids.size < 2
      return render json: { success: false, message: "取消には2名以上の従業員認証が必要です" }, status: :forbidden
    end

    owner = @current_pos.store.user
    employees = owner.employees.where(id: employee_ids)
    employees = employees.select { |e| e.is_all_stores || e.stores.exists?(@current_pos.store_id) }
    if employees.size < 2
      return render json: { success: false, message: "認証された従業員が不足しているか、店舗権限がありません" }, status: :forbidden
    end

    without_permission = employees.reject { |e| e.permitted?("refund") }
    if without_permission.any?
      names = without_permission.map(&:name).join("、")
      return render json: { success: false, message: "取消権限がありません: #{names}" }, status: :forbidden
    end

    reason = params[:reason].to_s.strip
    if reason.blank?
      return render json: { success: false, message: "取消理由を入力してください" }, status: :bad_request
    end

    error_message = nil
    ActiveRecord::Base.transaction do
      sale.lock!

      if sale.voided?
        error_message = "この会計はすでに取消済みです"
        raise ActiveRecord::Rollback
      end

      if sale.refunds.exists?
        error_message = "返品処理済みの会計は取消できません"
        raise ActiveRecord::Rollback
      end

      # 締め（精算）後の売上は取消不可。訂正が必要な場合は返品で対応する
      unless sale.register_session&.open?
        error_message = "精算済み（または旧形式）の売上は取消できません。返品で対応してください"
        raise ActiveRecord::Rollback
      end

      sale.update!(
        status: :voided,
        voided_at: Time.current,
        void_reason: reason,
        voided_by_employee: employees.first
      )

      # 在庫を全明細分戻す（reason: void で監査証跡を残す）
      sale.saledetails.each do |sd|
        product = sd.product
        next unless product
        store_stock = StoreStock.find_or_create_by!(store: sale.store, product: product)
        store_stock.with_lock do
          store_stock.increment!(:quantity, sd.quantity)
          StockMovement.create!(
            store: sale.store,
            product: product,
            store_stock: store_stock,
            sale: sale,
            pos_token: @current_pos,
            employee: employees.first,
            quantity_change: sd.quantity,
            reason: "void"
          )
        end
      end

      JournalEntry.create_from_void!(sale, employees.map(&:name))
    end

    if error_message
      return render json: { success: false, message: error_message }, status: :unprocessable_entity
    end

    render json: {
      success: true,
      sale_id: sale.id,
      receipt_number: sale.receipt_number,
      voided_at: sale.voided_at,
      total_amount: sale.total_amount
    }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  # POST /api/v1/sales/:id/issue_receipt — 領収書発行の記録
  # 発行履歴をジャーナルに残し、2回目以降は reissue（再発行）として返す。
  # クライアントは応答のインボイス記載事項（登録番号・税率別内訳）を使って印字する。
  def issue_receipt
    sale = Sale.where(store_id: @current_pos.store_id, user_id: @current_pos.store.user_id)
               .includes(:sale_tax_breakdowns)
               .find_by(id: params[:id])
    unless sale
      return render json: { success: false, message: "該当する会計が見つかりません" }, status: :not_found
    end

    if sale.voided?
      return render json: { success: false, message: "取消済みの会計には領収書を発行できません" }, status: :unprocessable_entity
    end

    employee = operator_employee
    addressee = params[:addressee].to_s.strip
    purpose = params[:purpose].to_s.strip.presence || "お品代として"

    reissue = false
    entry = nil
    ActiveRecord::Base.transaction do
      sale.lock!
      # 発行履歴から再発行かどうかを判定する（二重発行の防止表示）
      reissue = JournalEntry.receipt_issue.where(pos_token_id: sale.pos_token_id,
                                                 receipt_number: sale.receipt_number).exists?
      entry = JournalEntry.create_from_receipt_issue!(
        sale,
        employee: employee,
        addressee: addressee,
        purpose: purpose,
        reissue: reissue
      )
    end

    render json: {
      success: true,
      journal_entry_id: entry.id,
      reissue: reissue,
      receipt: {
        receipt_number: sale.receipt_number,
        total_amount: sale.total_amount,
        addressee: addressee,
        purpose: purpose,
        issued_at: entry.printed_at,
        invoice_registration_number: sale.user.invoice_registration_number,
        # 収入印紙が必要となる目安（5万円以上の営業に関する受取書）
        revenue_stamp_required: sale.total_amount >= 50_000,
        tax_breakdowns: sale.sale_tax_breakdowns.order(:tax_rate).map { |b|
          {
            tax_rate: b.tax_rate,
            tax_type: b.tax_type,
            taxable_amount: b.taxable_amount,
            amount_ex_tax: b.amount_ex_tax,
            tax_amount: b.tax_amount
          }
        }
      }
    }, status: :created
  end

  private

  # employee_id から担当者を特定し、店舗権限（全店舗権限 or 所属店舗）を確認する。
  # 不正な場合は 403 を描画して nil を返す。
  def resolve_employee(store)
    employee = store.user.employees.find_by(id: params[:employee_id])
    unless employee && (employee.is_all_stores || employee.stores.exists?(store.id))
      render json: { success: false, message: "担当者が見つからないか、店舗の権限がありません" },
             status: :forbidden
      return nil
    end
    employee
  end

  # create アクション用のストロングパラメータ
  def sale_params
    # receipt_number / sold_at はオフライン同期時にクライアントから送られてくる場合がある
    params.require(:sale).permit(:total_amount, :payment_method, :receipt_number, :subtotal_ex_tax, :tax_amount, :sold_at,
                                 :order_discount_type, :order_discount_value, :order_discount_reason)
  end

  # 現在開いているレジセッション（なければ nil = レガシー動作）
  def current_register_session
    return @current_register_session if defined?(@current_register_session)
    @current_register_session = @current_pos.register_sessions.open.first
  end

  # クライアントが送信した販売時刻（オフライン会計用）。不正な形式は無視する
  def client_sold_at
    value = sale_params[:sold_at]
    return nil if value.blank?
    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def operator_employee
    return @operator_employee if defined?(@operator_employee)
    employee_id = params[:employee_id].presence
    @operator_employee = employee_id ? @current_pos.store.user.employees.find_by(id: employee_id) : nil
  end

  # 支払い明細（複数）のパラメータを配列として取得
  # 例: payments: [{ method: 0, amount: 500 }, { method: 3, amount: 500, label: "Suica" }]
  def payment_params_array
    raw = params[:payments]
    return [] unless raw.is_a?(Array)

    raw.map do |p|
      attrs =
        if p.respond_to?(:permit)
          p.permit(:method, :amount, :label)
        else
          p
        end

      {
        method: attrs[:method].to_i,
        amount: attrs[:amount].to_i,
        label: attrs[:label].presence
      }
    end
  end

  # 受け取った支払い情報に応じてSaleレコードを構築する。
  # - 複数支払いが指定されている場合は合計金額の整合性をチェックし、
  #   payment_method カラムには「主たる支払い方法」（現金が含まれていれば現金、なければ最初）を保存する。
  # - 後方互換性のため、paymentsが無い場合は従来通り sale_params をそのまま使う。
  def build_sale(payments)
    if payments.present?
      total_from_payments = payments.sum { |p| p[:amount].to_i }
      total_amount = sale_params[:total_amount].to_i

      if total_from_payments != total_amount
        raise ActiveRecord::Rollback, "Total of payments (#{total_from_payments}) does not match sale total (#{total_amount})"
      end

      main_method =
        if payments.any? { |p| p[:method].to_i == Sale.payment_methods[:cash] }
          Sale.payment_methods[:cash]
        else
          payments.first[:method].to_i
        end

      Sale.new(
        total_amount: total_amount,
        payment_method: main_method,
        receipt_number: sale_params[:receipt_number],
        subtotal_ex_tax: sale_params[:subtotal_ex_tax].to_i,
        tax_amount: sale_params[:tax_amount].to_i
      )
    else
      Sale.new(sale_params)
    end
  end

  # 送信された明細（詳細）配列を Sale に紐づけて保存する。
  # セット商品コード付きは save_bundle_detail に委譲し、それ以外は通常商品として処理する。
  def save_sale_details
    details = params[:details]
    return unless details.is_a?(Array)

    details.each do |detail|
      attrs = detail.respond_to?(:permit) ?
        detail.permit(:product_id, :product_name, :product_code, :quantity, :unit_price, :subtotal,
                      :tax_rate, :tax_amount, :tax_type, :bundle_code, :original_unit_price, :discount_reason) :
        detail

      # セット商品コードが指定されている場合はセット展開
      bundle_code = attrs[:bundle_code].presence
      if bundle_code
        save_bundle_detail(bundle_code, attrs)
        next
      end

      # 通常商品: id または code で解決
      product = nil
      product = @sale.user.products.find_by(id: attrs[:product_id]) if attrs[:product_id].present?
      product = @sale.user.products.find_by(code: attrs[:product_code]) if product.nil? && attrs[:product_code].present?
      next if product.nil?

      # tax_rate / tax_type: クライアント送信値を優先、なければ商品マスタから取得
      # （販売時点の値として明細に凍結する）
      tax_rate = attrs[:tax_rate].present? ? attrs[:tax_rate].to_i : product.tax_rate
      tax_type = detail_tax_type(attrs[:tax_type], product)
      unit_price = attrs[:unit_price].to_i

      raise ArgumentError, "明細の単価が負の値です: #{product.name}" if unit_price < 0

      quantity = attrs[:quantity].to_i
      subtotal = attrs[:subtotal].present? ? attrs[:subtotal].to_i : unit_price * quantity
      tax_amount = line_tax_amount(subtotal, tax_rate, tax_type)

      # 割引追跡: クライアントから original_unit_price が送られた場合に割引額を計算
      original_unit_price = attrs[:original_unit_price].present? ? attrs[:original_unit_price].to_i : nil
      discount_amount = if original_unit_price.present? && original_unit_price > unit_price
        (original_unit_price - unit_price) * quantity
      else
        0
      end
      discount_reason = attrs[:discount_reason].presence

      sale_detail = @sale.saledetails.create!(
        product_id: product.id,
        product_name: attrs[:product_name].presence || product.name,
        quantity: quantity,
        unit_price: unit_price,
        subtotal: subtotal,
        tax_rate: tax_rate,
        tax_type: tax_type,
        tax_amount: tax_amount,
        original_unit_price: original_unit_price,
        discount_amount: discount_amount,
        discount_reason: discount_reason
      )

      deduct_stock(@sale.store, product, sale_detail.quantity, operator_employee)
    end
  end

  # 企業設定の端数処理方式に従う税計算機
  def tax_calculator
    @tax_calculator ||= TaxCalculator.new(@sale.user.tax_rounding_method)
  end

  # 明細行の税額（表示用参考値。会計単位の確定値は sale_tax_breakdowns が持つ）
  def line_tax_amount(subtotal, tax_rate, tax_type)
    tax_calculator.line_tax(subtotal, tax_rate, tax_type)
  end

  # 明細の税区分: クライアント送信値（enum名 or 数値）を優先、なければ商品マスタ
  def detail_tax_type(client_value, product)
    if client_value.present?
      value = client_value.to_s
      return value if Saledetail.tax_types.key?(value)
      if value.match?(/\A\d+\z/)
        name = Saledetail.tax_types.key(value.to_i)
        return name if name
      end
    end
    product.tax_type
  end

  # 小計割引（会計全体への金額/％割引）を明細へ按分する。
  # 明細の subtotal を割引後の「実際に請求した額」に更新してから税計算するため、
  # 税率別内訳・返品・レポートすべてが割引後の金額で整合する。
  # 端数は最後の明細に寄せて割引合計と一致させる。
  def apply_order_discount
    type_param = sale_params[:order_discount_type]
    return if type_param.blank?

    type = normalize_discount_type(type_param)
    raise ArgumentError, "割引種別が不正です" unless type

    value = sale_params[:order_discount_value].to_i
    raise ArgumentError, "割引値は1以上を指定してください" if value <= 0

    employee = operator_employee
    unless employee&.permitted?("discount")
      raise ArgumentError, "小計割引の権限がありません"
    end

    # 後続の税計算（save_tax_breakdowns）が同じインスタンスを参照するため、
    # 新規クエリではなくアソシエーションにロード済みのオブジェクトを更新する
    details = @sale.saledetails.sort_by(&:id)
    raise ArgumentError, "割引対象の明細がありません" if details.empty?

    base_total = details.sum(&:subtotal)
    discount_total =
      if type == "percent"
        raise ArgumentError, "割引率は1〜100で指定してください" if value > 100
        base_total * value / 100
      else
        value
      end

    raise ArgumentError, "割引額が明細合計を超えています" if discount_total > base_total
    return if discount_total <= 0

    allocated = details.map { |d| discount_total * d.subtotal / base_total }
    allocated[-1] += discount_total - allocated.sum

    reason = sale_params[:order_discount_reason].presence
    details.each_with_index do |detail, idx|
      next if allocated[idx] <= 0
      new_subtotal = detail.subtotal - allocated[idx]
      detail.update!(
        original_unit_price: detail.original_unit_price || detail.unit_price,
        unit_price: new_subtotal / detail.quantity,
        subtotal: new_subtotal,
        tax_amount: line_tax_amount(new_subtotal, detail.tax_rate, detail.tax_type),
        discount_amount: detail.discount_amount + allocated[idx],
        discount_reason: detail.discount_reason.presence || reason
      )
    end

    @sale.update_columns(
      order_discount_type: Sale.order_discount_types[type],
      order_discount_value: value,
      order_discount_total: discount_total,
      order_discount_reason: reason
    )
  end

  # 割引種別: enum 名（"amount"/"percent"）と数値コードの両方を受け付ける
  def normalize_discount_type(value)
    name = value.to_s
    return name if Sale.order_discount_types.key?(name)
    if name.match?(/\A\d+\z/)
      Sale.order_discount_types.key(name.to_i)
    end
  end

  # 税率別内訳の確定保存（適格簡易請求書の記載事項）。
  # 「1レシートにつき税率ごとに端数処理1回」のため、明細積み上げではなくここで確定する。
  # ヘッダーの税額・税抜額も内訳の合計で上書きし、集計と常に一致させる。
  def save_tax_breakdowns
    details = @sale.saledetails.to_a
    return if details.empty?

    lines = details.map { |d| { amount: d.subtotal, tax_rate: d.tax_rate, tax_type: d.tax_type } }
    results = tax_calculator.breakdowns(lines)

    results.each do |r|
      @sale.sale_tax_breakdowns.create!(
        tax_rate: r.tax_rate,
        tax_type: r.tax_type,
        taxable_amount: r.taxable_amount,
        amount_ex_tax: r.amount_ex_tax,
        tax_amount: r.tax_amount
      )
    end

    # 整合性検証: 会計合計 = 税率別内訳の税込対価合計
    total_taxable = results.sum(&:taxable_amount)
    if total_taxable != @sale.total_amount
      raise ArgumentError, "明細の合計(#{total_taxable}円)が会計合計(#{@sale.total_amount}円)と一致しません"
    end

    @sale.update_columns(
      subtotal_ex_tax: results.sum(&:amount_ex_tax),
      tax_amount: results.sum(&:tax_amount)
    )
  end

  # セット商品を構成商品に展開して売上明細を作成する。
  # 売上への計上額は構成品の定価ではなく「バンドル販売価格」
  # （クライアント送信の subtotal、なければマスタの bundle.price × 数量）を
  # 構成品の定価比で按分し、端数は最後の構成品に寄せて合計を一致させる。
  def save_bundle_detail(bundle_code, attrs)
    bundle = @sale.user.product_bundles.includes(product_bundle_items: :product).find_by(code: bundle_code)
    return unless bundle

    bundle_qty = attrs[:quantity].to_i
    bundle_qty = 1 if bundle_qty <= 0

    bundle_total = attrs[:subtotal].present? ? attrs[:subtotal].to_i : bundle.price * bundle_qty
    raise ArgumentError, "セット商品の金額が負の値です: #{bundle.name}" if bundle_total < 0

    items = bundle.product_bundle_items.select(&:product)
    return if items.empty?

    # 定価合計を重みに按分する。全構成品が0円の場合は数量比で按分する。
    weights = items.map { |item| item.product.price * item.quantity * bundle_qty }
    if weights.sum <= 0
      weights = items.map { |item| item.quantity * bundle_qty }
    end
    weight_sum = weights.sum

    allocated = weights.map { |w| bundle_total * w / weight_sum }
    allocated[-1] += bundle_total - allocated.sum

    items.each_with_index do |item, idx|
      product = item.product
      item_qty = item.quantity * bundle_qty
      subtotal = allocated[idx]
      unit_price = subtotal / item_qty
      tax_rate = product.tax_rate
      # バンドル販売価格は「支払額」なので、構成品の税区分によらず税込（内税）として扱う
      tax_amount = line_tax_amount(subtotal, tax_rate, :inclusive)

      @sale.saledetails.create!(
        product_id: product.id,
        product_name: product.name,
        quantity: item_qty,
        unit_price: unit_price,
        subtotal: subtotal,
        tax_rate: tax_rate,
        tax_type: :inclusive,
        tax_amount: tax_amount
      )

      deduct_stock(@sale.store, product, item_qty, operator_employee)
    end
  end

  # 店舗在庫を数量分だけ減らし、監査証跡として在庫変動履歴を残す
  def deduct_stock(store, product, quantity, employee = nil)
    return if store.nil? || quantity <= 0

    store_stock = StoreStock.find_or_create_by!(store: store, product: product)
    store_stock.with_lock do
      store_stock.quantity = (store_stock.quantity || 0) - quantity
      store_stock.save!
      StockMovement.create!(
        store: store,
        product: product,
        store_stock: store_stock,
        sale: @sale,
        pos_token: @sale.pos_token,
        employee: employee,
        quantity_change: -quantity,
        reason: "sale"
      )
    end
  end

  # 支払い情報を sale_payments に保存する。
  # - payments が空の場合は、後方互換性として Sale.payment_method 全額の1行を作成する。
  def save_sale_payments(payments)
    if payments.present?
      payments.each do |p|
        @sale.sale_payments.create!(
          method: p[:method],
          amount: p[:amount],
          label: p[:label]
        )
      end
    else
      @sale.sale_payments.create!(
        method: @sale.payment_method_before_type_cast,
        amount: @sale.total_amount
      )
    end
  end
end
