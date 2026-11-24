# 売上（会計）に関するAPI。会計の登録（create）に加え、日次一覧、期間集計、
# 取消（void）、領収書発行の記録を扱う。
class Api::V1::SalesController < Api::V1::BaseController
  # 冪等キー（client_request_id）として受け付ける形式（UUID 等の英数字・ハイフン）
  CLIENT_REQUEST_ID_FORMAT = /\A[0-9A-Za-z-]{8,64}\z/

  # オフライン会計で端末が先に採番できる連番の上限（サーバーの次番号からの差）。連番の食い潰しを防ぐ
  MAX_OFFLINE_SEQUENCE_AHEAD = 10_000

  # 会計を受け付けられない理由（端末側が対応を分岐できるよう code を付ける）
  class RejectedSale < StandardError
    attr_reader :code, :status

    def initialize(message, code:, status: :unprocessable_entity)
      super(message)
      @code = code
      @status = status
    end
  end

  # GET /api/v1/sales?date=YYYY-MM-DD&employee_id=... — 指定日（省略時は当日）の自店舗の売上一覧。
  # 店舗の売上を閲覧するため view_sales 権限を持つ担当者のみ。
  def index
    employee = require_store_employee!(params[:employee_id])
    return unless employee

    authorize_employee!(employee, "view_sales")
    return if performed?

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
          status: s.status,
          voidable: s.completed? && s.register_session_id.present? && s.register_session_id == current_register_session&.id,
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
    employee = require_store_employee!(params[:employee_id])
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
    payment_totals = payments_scope.group(:method).sum(:amount)
    payment_breakdown = PaymentMethods::VALUES.keys.to_h { |name| [ name, payment_totals.fetch(name.to_s, 0) ] }

    # 客層キー（性別・年代）別の売上集計。未選択（NULL）は集計対象から除く
    customer_segment_breakdown = sales
      .where.not(customer_gender: nil)
      .where.not(customer_age_group: nil)
      .group(:customer_gender, :customer_age_group)
      .select(Arel.sql("customer_gender, customer_age_group, COUNT(*) AS segment_count, SUM(total_amount) AS segment_amount"))
      .map do |row|
        {
          gender:    row.customer_gender,
          age_group: row.customer_age_group,
          count:     row.segment_count.to_i,
          amount:    row.segment_amount.to_i
        }
      end

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
      top_products:      top_products.map { |p| { product_name: p.product_name, quantity: p.total_qty.to_i, amount: p.total_amount.to_i } },
      customer_segment_breakdown: customer_segment_breakdown
    }
  rescue ArgumentError
    render json: { success: false, message: "日付の形式が不正です" }, status: :bad_request
  end

  # POST /api/v1/sales — 会計（売上）を登録する。
  # Sale作成 → 明細保存 → 小計割引適用 → 支払い保存 → 税率別内訳確定、の順で処理し、
  # 失敗時はロールバックしてエラーを返す。
  #
  # client_request_id（冪等キー）が指定され、この端末で同じキーの会計が登録済みなら、
  # 新たに登録せず既存の会計を 200 で返す（タイムアウト後の再送による二重計上の防止）。
  def create
    request_id = params[:client_request_id].presence&.to_s
    if request_id && !request_id.match?(CLIENT_REQUEST_ID_FORMAT)
      return render json: { success: false, errors: [ "client_request_id の形式が不正です" ] }, status: :unprocessable_entity
    end

    if request_id && (existing = @current_pos.sales.find_by(client_request_id: request_id))
      return render_registered_sale(existing)
    end

    # 「誰が」（担当者）と「何を」（明細）が欠けた会計は売上分析・監査で追跡できないため受け付けない
    unless operator_employee
      return render json: { success: false, errors: [ "担当者（employee_id）が指定されていないか、この店舗を操作できません" ] }, status: :unprocessable_entity
    end
    unless params[:details].is_a?(Array) && params[:details].any?
      return render json: { success: false, errors: [ "明細（details）が1件以上必要です" ] }, status: :unprocessable_entity
    end

    # 適用日を迎えた価格・税率の変更を反映してから計算する
    ScheduledProductChange.apply_due!(@current_pos.store.user)

    # BaseControllerのauthenticate_pos_tokenでセットされた @current_pos を使用
    payments = payment_params_array

    @sale = build_sale(payments)
    @sale.pos_token = @current_pos
    @sale.store = @current_pos.store
    @sale.user = @current_pos.store.user
    @sale.employee = operator_employee
    @sale.client_request_id = request_id
    @sale.age_verified = ActiveModel::Type::Boolean.new.cast(params[:age_verified]) || false

    @sale.offline = offline_sale?
    @review_reasons = []
    assign_accounting_context

    ActiveRecord::Base.transaction do
      assign_customer
      if @sale.save
        # 明細作成 → 小計割引反映 → 支払い保存 → 税率別内訳確定の順で処理する
        save_sale_details
        apply_set_promotions
        apply_coupon
        apply_order_discount
        save_sale_payments(payments)
        save_tax_breakdowns
        Loyalty.apply_sale!(@sale, recorded_payments(payments))

        # Saleモデルのコールバックで pos_token.next_receipt_sequence がインクリメントされているため、
        # 最新の状態をリロードして取得し、クライアントへ返す（オフライン会計用）
        next_sequence = @current_pos.reload.next_receipt_sequence
        # 割引合計を明細から集計してヘッダーに反映
        @sale.update_columns(
          total_discount: @sale.saledetails.sum(:discount_amount),
          discount_approver_id: @discount_approver&.id,
          review_reasons: @review_reasons.uniq
        )

        JournalEntry.create_from_sale!(@sale, @sale.saledetails, payments)

        render json: {
          success: true,
          sale_id: @sale.id,
          receipt_number: @sale.receipt_number,
          next_receipt_sequence: next_sequence,
          receipt_url: digital_receipt_url(@sale),
          points_earned: @sale.points_earned,
          points_balance: @sale.customer&.reload&.points
        }, status: :created
        publish_sale_created
      else
        # レシート番号の重複は再送しても解消しないため 409 で区別して返す
        status = @sale.errors.of_kind?(:receipt_number, :taken) ? :conflict : :unprocessable_entity
        render json: { success: false, errors: @sale.errors.full_messages }, status: status
        raise ActiveRecord::Rollback
      end
    end
  rescue RejectedSale => e
    render json: { success: false, code: e.code, errors: [ e.message ] }, status: e.status
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, errors: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue ArgumentError, RangeError => e
    render json: { success: false, errors: [ e.message ] }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    # 同じ冪等キーの同時送信は、先に登録された会計を返す。それ以外はレシート番号の重複
    existing = request_id && @current_pos.sales.find_by(client_request_id: request_id)
    if existing
      render_registered_sale(existing)
    else
      render json: { success: false, errors: [ "レシート番号が重複しています" ] }, status: :conflict
    end
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

    employees = require_dual_approval!(params[:employee_ids], "refund", action_label: "取消")
    return unless employees

    reason = params[:reason].to_s.strip
    if reason.blank?
      return render json: { success: false, message: "取消理由を入力してください" }, status: :bad_request
    end

    error_message = nil
    # 取消可否の判定と在庫戻し・状態更新をまとめて1トランザクションで行う
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

      unless consume_approvals(employees, "refund", "void:#{sale.receipt_number}")
        error_message = "担当者の認証がすでに使用されています。もう一度認証してください"
        raise ActiveRecord::Rollback
      end

      sale.update!(
        status: :voided,
        voided_at: Time.current,
        void_reason: reason,
        voided_by_employee: employees.first
      )

      # 在庫を全明細分戻し、ポイント・クーポンも元に戻す
      sale.saledetails.each do |sd|
        next unless sd.product

        StoreStock.adjust!(store: sale.store, product: sd.product, change: sd.quantity, reason: "void",
                           employee: employees.first, pos_token: @current_pos, sale: sale)
      end
      Loyalty.apply_void!(sale)

      JournalEntry.create_from_void!(sale, employees.map(&:name))
    end

    if error_message
      return render json: { success: false, message: error_message }, status: :unprocessable_entity
    end

    Webhook.publish(sale.user, "sale.voided", SalePayload.sale(sale))
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
    unless employee
      return render json: { success: false, message: EmployeePermissionAuthorizable::STORE_EMPLOYEE_NOT_FOUND }, status: :forbidden
    end

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

  # 登録済みの会計（冪等キーによる再送）を、新規登録時と同じ形式で返す
  def render_registered_sale(sale)
    render json: {
      success: true,
      duplicate: true,
      sale_id: sale.id,
      receipt_number: sale.receipt_number,
      next_receipt_sequence: @current_pos.reload.next_receipt_sequence
    }, status: :ok
  end

  # create アクション用のストロングパラメータ
  def sale_params
    # receipt_number / sold_at はオフライン同期時にクライアントから送られてくる場合がある
    params.require(:sale).permit(:total_amount, :payment_method, :receipt_number, :subtotal_ex_tax, :tax_amount, :sold_at,
                                 :order_discount_type, :order_discount_value, :order_discount_reason,
                                 :customer_gender, :customer_age_group, :coupon_code, :promotion_discount_total)
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
    @operator_employee = employee_id ? find_store_employee(employee_id) : nil
  end

  # 支払い明細（複数）のパラメータを配列として取得
  # 例: payments: [{ method: 0, amount: 500 }, { method: 3, amount: 500, label: "Suica" }]
  def payment_params_array
    raw = params[:payments]
    return [] unless raw.is_a?(Array)

    raw.map do |p|
      attrs =
        if p.respond_to?(:permit)
          p.permit(:method, :amount, :label, :external_reference, :terminal_provider)
        else
          p
        end

      {
        method: attrs[:method].to_i,
        amount: attrs[:amount].to_i,
        label: attrs[:label].presence,
        external_reference: attrs[:external_reference].presence&.to_s&.slice(0, 100),
        terminal_provider: attrs[:terminal_provider].presence&.to_s&.slice(0, 40)
      }
    end
  end

  # 受け取った支払い情報に応じてSaleレコードを構築する。
  # - 複数支払いが指定されている場合は合計金額の整合性をチェックし、
  #   payment_method カラムには「主たる支払い方法」（現金が含まれていれば現金、なければ最初）を保存する。
  # - 後方互換性のため、paymentsが無い場合は従来通り sale_params をそのまま使う。
  def recorded_payments(payments)
    payments.presence || [ { method: @sale.payment_method_before_type_cast, amount: @sale.total_amount } ]
  end

  # トランザクションの確定後に外部へ通知する
  def publish_sale_created
    sale = @sale
    ActiveRecord.after_all_transactions_commit { Webhook.publish(sale.user, "sale.created", SalePayload.sale(sale)) }
  end

  def digital_receipt_url(sale)
    digital_receipt_full_url(sale.public_token) if sale.user.digital_receipt_enabled
  end

  def assign_customer
    code = params[:customer_code].presence&.to_s
    return unless code

    @sale.customer = @sale.user.customers.active.find_by(code: code)
    return if @sale.customer

    message = "会員が見つかりません: #{code.slice(0, 32)}"
    @sale.offline? ? @review_reasons << message : raise(RejectedSale.new(message, code: "customer_not_found"))
  end

  def build_sale(payments)
    if payments.present?
      total_from_payments = payments.sum { |p| p[:amount].to_i }
      total_amount = sale_params[:total_amount].to_i

      if total_from_payments != total_amount
        raise ArgumentError, "Total of payments (#{total_from_payments}) does not match sale total (#{total_amount})"
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
        receipt_number: client_receipt_number,
        subtotal_ex_tax: sale_params[:subtotal_ex_tax].to_i,
        tax_amount: sale_params[:tax_amount].to_i,
        customer_gender: sale_params[:customer_gender].presence,
        customer_age_group: sale_params[:customer_age_group].presence
      )
    else
      Sale.new(sale_params.except(:coupon_code, :promotion_discount_total, :sold_at).merge(receipt_number: client_receipt_number))
    end
  end

  # オフライン会計でクライアントが採番したレシート番号。
  # 自端末の連番形式（末尾が "-{POS端末ID}-{8桁連番}"）のものだけ採用し、それ以外は破棄して
  # サーバー側で採番する。他端末・他社のレシート番号を先取りして採番を妨害されるのを防ぐ。
  def client_receipt_number
    value = sale_params[:receipt_number].to_s
    match = value.match(/\A[A-Za-z0-9]+-[A-Za-z0-9]+-(\d+)-(\d{8})\z/)
    return unless match && match[1].to_i == @current_pos.id

    value if match[2].to_i.between?(1, @current_pos.next_receipt_sequence + MAX_OFFLINE_SEQUENCE_AHEAD)
  end

  # オフライン会計の後送か（端末がレシート番号を採番済みの会計）
  def offline_sale?
    client_receipt_number.present?
  end

  # 販売時刻・営業日・レジセッションを決める。
  # オンライン会計はサーバーの時刻を使う。オフライン会計は端末の販売時刻を使い、その時刻に開いていた
  # レジセッション（＝実際に現金を受け取った営業日）に計上する。
  def assign_accounting_context
    now = Time.current
    session = current_register_session
    @sale.sold_at = now
    if @sale.offline? && (sold_at = client_sold_at)
      if sold_at > now + 5.minutes
        @review_reasons << "販売時刻が未来のため、受信時刻で登録しました"
      else
        @sale.sold_at = sold_at
        session = session_at(sold_at) || session
        @review_reasons << "レジ精算の後に届いたオフライン会計です" if session&.closed?
      end
    end

    @sale.register_session = session
    covered = session && session.opened_at <= @sale.sold_at
    @sale.business_date = covered ? session.business_date : @sale.sold_at.in_time_zone.to_date
  end

  def session_at(time)
    @current_pos.register_sessions
                .where("opened_at <= ?", time)
                .where("closed_at IS NULL OR closed_at >= ?", time)
                .order(opened_at: :desc).first
  end

  def price_policy
    @price_policy ||= SalePricePolicy.new(store: @sale.store, sold_at: @sale.sold_at)
  end

  # 通常価格と異なる単価での販売を認める担当者（discount 権限＋PIN認証）。操作者と別の責任者でもよい
  def discount_approver
    return @discount_approver if defined?(@discount_approver)

    @discount_approver = approved_employee_for("discount")
    if @discount_approver.nil? && EmployeePermissionAuthorizable.legacy_operator_auth_allowed?
      @discount_approver = operator_employee if operator_employee&.permitted?("discount")
    end
    @discount_approver
  end

  # 権限のない価格変更を拒否する。オフライン会計は販売済みの事実を失わないよう登録し、要確認にする
  def require_discount_approval!(message)
    return if discount_approver

    if @sale.offline?
      @review_reasons << message
    else
      raise RejectedSale.new("#{message}。値引き権限を持つ担当者の認証が必要です", code: "discount_approval_required", status: :forbidden)
    end
  end

  # 明細の税率がマスタと異なる場合、オンラインなら端末のマスタ更新を促して拒否し、オフラインなら要確認にする
  def check_tax!(product, tax_rate, tax_type, eat_in)
    return if price_policy.tax_rate?(product, tax_rate, eat_in: eat_in) && tax_type.to_s == product.tax_type

    message = "税率・税区分がマスタと異なります: #{product.name}"
    if @sale.offline?
      @review_reasons << message
    else
      raise RejectedSale.new("#{message}。商品マスタを同期してください", code: "master_outdated", status: :conflict)
    end
  end

  DETAIL_KEYS = [ :product_id, :product_name, :product_code, :quantity, :unit_price, :subtotal, :tax_rate, :tax_amount, :tax_type, :bundle_code,
                  :original_unit_price, :discount_reason, :weight_grams, :service_type, { options: [] } ].freeze

  # 送信された明細（詳細）配列を Sale に紐づけて保存する。
  # セット商品コード付きは save_bundle_detail に委譲し、それ以外は通常商品として処理する。
  def save_sale_details
    @promotion_lines = []
    params[:details].each do |detail|
      attrs = detail.respond_to?(:permit) ? detail.permit(*DETAIL_KEYS) : detail
      bundle_code = attrs[:bundle_code].presence
      # 旧バージョンの端末はセット商品を構成商品ごとの明細で送る（product_id あり）。
      # その明細をさらにセットとして展開すると数量・在庫が重複するため、通常の商品として扱う
      bundle_code && attrs[:product_id].blank? ? save_bundle_detail(bundle_code, attrs) : save_product_detail(attrs)
    end
  end

  # 通常商品の明細を、価格・税率・年齢確認を検証して保存する
  def save_product_detail(attrs)
    product = find_detail_product(attrs)
    eat_in = attrs[:service_type].to_s.in?(%w[eat_in 1])

    # tax_rate / tax_type: クライアント送信値を優先、なければ商品マスタから取得
    # （販売時点の値として明細に凍結する）
    tax_rate = attrs[:tax_rate].present? ? attrs[:tax_rate].to_i : price_policy.tax_rates(product, eat_in: eat_in).first
    tax_type = detail_tax_type(attrs[:tax_type], product)
    unit_price = attrs[:unit_price].to_i
    raise ArgumentError, "明細の単価が負の値です: #{product.name}" if unit_price < 0

    check_tax!(product, tax_rate, tax_type, eat_in)
    check_age!(product)
    options = resolve_options(product, attrs[:options])
    options_price = options.sum { |o| o["price"] }

    # 量り売り（計量）商品: price は100gあたりの単価。重量(g)の入力が必須
    weight_grams = attrs[:weight_grams].presence&.to_i if product.sold_by_weight
    if product.sold_by_weight && (weight_grams.blank? || weight_grams <= 0)
      raise ArgumentError, "量り売り商品には重量(g)の指定が必要です: #{product.name}"
    end

    quantity = attrs[:quantity].to_i
    raise ArgumentError, "明細の数量は1以上を指定してください: #{product.name}" if quantity <= 0
    subtotal = SalePricePolicy.expected_subtotal(unit_price: unit_price, quantity: quantity, weight_grams: weight_grams)
    if attrs[:subtotal].present? && attrs[:subtotal].to_i != subtotal
      raise ArgumentError, "明細の小計が単価・数量と一致しません: #{product.name}"
    end

    # 通常価格・タイムセール以外の単価は値引き（価格変更）。権限を確認し、割引額はサーバーの通常価格から計算する
    price_kind = price_policy.classify(product, unit_price, eat_in: eat_in, options_price: options_price)
    original_unit_price = nil
    discount_amount = 0
    unless price_kind == :regular
      require_discount_approval!("通常と異なる価格で販売しています: #{product.name}（#{unit_price}円）") if price_kind.nil?
      original_unit_price = price_policy.base_price(product, eat_in: eat_in) + options_price
      regular = SalePricePolicy.expected_subtotal(unit_price: original_unit_price, quantity: quantity, weight_grams: weight_grams)
      discount_amount = [ regular - subtotal, 0 ].max
    end
    promotion = price_kind if price_kind.is_a?(Promotion)

    sale_detail = @sale.saledetails.create!(
      product_id: product.id,
      product_name: attrs[:product_name].presence || product.name,
      quantity: quantity,
      unit_price: unit_price,
      subtotal: subtotal,
      tax_rate: tax_rate,
      tax_type: tax_type,
      tax_amount: line_tax_amount(subtotal, tax_rate, tax_type),
      original_unit_price: original_unit_price,
      discount_amount: discount_amount,
      discount_reason: attrs[:discount_reason].presence || promotion&.name,
      promotion_name: promotion&.name,
      weight_grams: weight_grams,
      service_type: eat_in ? :eat_in : :takeout,
      options: options,
      cost_price: product.cost_price
    )
    @promotion_lines << PromotionLine.new(detail: sale_detail, product: product, quantity: quantity, unit_price: unit_price,
                                          eligible: price_kind == :regular && weight_grams.nil?)
    deduct_stock(@sale.store, product, quantity, operator_employee)
  end

  PromotionLine = Struct.new(:detail, :product, :quantity, :unit_price, :eligible, keyword_init: true)

  # 商品を id または code で特定する。
  # 特定できない明細を黙って捨てると「何を売ったか」が記録から欠落するため、会計ごと拒否する
  def find_detail_product(attrs)
    products = @sale.user.products
    product = products.find_by(id: attrs[:product_id]) if attrs[:product_id].present?
    product ||= products.find_by(code: attrs[:product_code]) if attrs[:product_code].present?
    product || raise(ArgumentError, "明細の商品が見つかりません: #{attrs[:product_name].presence || attrs[:product_code].presence || attrs[:product_id]}")
  end

  # 選択されたオプション（トッピング等）をマスタから取得し、選択数を確認する
  def resolve_options(product, ids)
    ids = Array(ids).map(&:to_i)
    groups = product.option_groups.includes(:option_items).to_a
    return [] if ids.empty? && groups.all? { |g| g.min_select.zero? }

    items = groups.flat_map { |g| g.option_items.select { |item| ids.include?(item.id) } }
    raise ArgumentError, "選択できないオプションが含まれています: #{product.name}" if items.size != ids.uniq.size || ids.uniq.size != ids.size

    groups.each do |group|
      count = items.count { |item| item.option_group_id == group.id }
      unless count.between?(group.min_select, group.max_select)
        raise ArgumentError, "「#{group.name}」は#{group.min_select}〜#{group.max_select}個選択してください: #{product.name}"
      end
    end
    items.map { |item| { "id" => item.id, "name" => item.name, "price" => item.price } }
  end

  # 年齢確認が必要な商品（酒・たばこ等）
  def check_age!(product)
    return if product.min_age.nil? || @sale.age_verified

    message = "#{product.min_age}歳以上であることの確認が必要です: #{product.name}"
    @sale.offline? ? @review_reasons << message : raise(RejectedSale.new(message, code: "age_verification_required"))
  end

  # まとめ買い割引。端末が計算した額（promotion_discount_total）をサーバーで再計算して照合する。
  # 送られていない場合（未対応の端末）は適用しない
  def apply_set_promotions
    claimed = sale_params[:promotion_discount_total].to_i
    return if claimed.zero?

    discounts = price_policy.promotions.set_discounts(@promotion_lines)
    expected = discounts.sum(&:amount)
    if claimed != expected
      message = "まとめ買い割引の額が異なります（端末 #{claimed}円 / サーバー #{expected}円）"
      raise RejectedSale.new("#{message}。商品マスタを同期してください", code: "master_outdated", status: :conflict) unless @sale.offline?

      @review_reasons << message
      allocate_discount(@sale.saledetails.to_a, claimed, "まとめ買い割引")
    else
      discounts.each do |d|
        allocate_discount(d.lines.map(&:detail), d.amount, d.promotion.name)
        d.lines.each { |line| line.detail.update!(promotion_name: d.promotion.name) }
      end
    end
    @sale.update_columns(promotion_discount_total: claimed)
  end

  # クーポン（会計の小計からの割引。権限者の承認は不要）
  def apply_coupon
    code = sale_params[:coupon_code].presence
    return unless code
    raise ArgumentError, "クーポンと小計割引は併用できません" if sale_params[:order_discount_type].present?

    coupon = @sale.user.coupons.find_by(code: code.to_s.strip.upcase)
    raise RejectedSale.new("クーポンが見つかりません", code: "coupon_invalid") unless coupon

    details = @sale.saledetails.to_a
    total = details.sum(&:subtotal)
    discount = coupon.discount_for(total)
    begin
      coupon.redeem!(total, @sale.business_date)
    rescue Coupon::Unusable => e
      raise RejectedSale.new(e.message, code: "coupon_invalid") unless @sale.offline?

      @review_reasons << "#{e.message}（#{coupon.name}）"
    end
    allocate_discount(details, discount, coupon.name)
    @sale.update_columns(coupon_id: coupon.id, order_discount_type: Sale.order_discount_types[coupon.discount_type],
                         order_discount_value: coupon.discount_value, order_discount_total: discount, order_discount_reason: coupon.name)
  end

  # 割引額を明細へ按分する（端数は最後の明細に寄せる）。
  # 明細の subtotal を「実際に請求した額」に更新するため、税率別内訳・返品・レポートすべてが割引後の金額で整合する。
  def allocate_discount(details, discount_total, reason)
    details = details.sort_by(&:id)
    base_total = details.sum(&:subtotal)
    raise ArgumentError, "割引対象の明細がありません" if details.empty?
    raise ArgumentError, "割引額が明細合計を超えています" if discount_total > base_total
    return if discount_total <= 0

    allocated = details.map { |d| discount_total * d.subtotal / base_total }
    remainder = discount_total - allocated.sum
    # 端数は金額に余裕のある明細に寄せる（0円の明細が負にならないように）
    allocated[details.rindex { |d| d.subtotal - allocated[details.index(d)] >= remainder }] += remainder

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

    require_discount_approval!("小計割引が適用されています")

    # 後続の税計算（save_tax_breakdowns）が同じインスタンスを参照するため、
    # 新規クエリではなくアソシエーションにロード済みのオブジェクトを更新する
    details = @sale.saledetails.to_a
    raise ArgumentError, "割引対象の明細がありません" if details.empty?

    base_total = details.sum(&:subtotal)
    discount_total =
      if type == "percent"
        raise ArgumentError, "割引率は1〜100で指定してください" if value > 100
        base_total * value / 100
      else
        value
      end
    return if discount_total <= 0

    reason = sale_params[:order_discount_reason].presence
    allocate_discount(details, discount_total, reason)

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
    raise ArgumentError, "セット商品が見つかりません: #{bundle_code}" unless bundle

    bundle_qty = attrs[:quantity].to_i
    bundle_qty = 1 if bundle_qty <= 0

    bundle_total = attrs[:subtotal].present? ? attrs[:subtotal].to_i : (bundle.price.positive? ? bundle.price : items_total(bundle)) * bundle_qty
    raise ArgumentError, "セット商品の金額が負の値です: #{bundle.name}" if bundle_total < 0

    # セット価格が0円の場合は構成商品の合計で販売する
    expected_total = (bundle.price.positive? ? bundle.price : items_total(bundle)) * bundle_qty
    if bundle_total != expected_total
      require_discount_approval!("セット商品が通常と異なる価格で販売されています: #{bundle.name}（#{bundle_total}円）")
    end

    items = bundle.product_bundle_items.select(&:product)
    raise ArgumentError, "セット商品に構成商品がありません: #{bundle.name}" if items.empty?

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
      tax_rate = price_policy.tax_rates(product).first
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
        tax_amount: tax_amount,
        cost_price: product.cost_price
      )
      check_age!(product)

      deduct_stock(@sale.store, product, item_qty, operator_employee)
    end
  end

  def items_total(bundle)
    bundle.product_bundle_items.sum { |item| item.product ? price_policy.base_price(item.product) * item.quantity : 0 }
  end

  # 店舗在庫を数量分だけ減らし、監査証跡として在庫変動履歴を残す
  def deduct_stock(store, product, quantity, employee = nil)
    return if store.nil? || quantity <= 0

    StoreStock.adjust!(store: store, product: product, change: -quantity, reason: "sale", employee: employee, pos_token: @sale.pos_token, sale: @sale)
  end

  # 支払い情報を sale_payments に保存する。
  # - payments が空の場合は、後方互換性として Sale.payment_method 全額の1行を作成する。
  def save_sale_payments(payments)
    if payments.present?
      payments.each do |p|
        @sale.sale_payments.create!(
          method: p[:method],
          amount: p[:amount],
          label: p[:label],
          external_reference: p[:external_reference],
          terminal_provider: p[:terminal_provider]
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
