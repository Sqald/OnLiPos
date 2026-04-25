class Api::V1::SalesController < Api::V1::BaseController 
  def create
    # BaseControllerのauthenticate_pos_tokenでセットされた @current_pos を使用
    payments = payment_params_array

    @sale = build_sale(payments)
    @sale.pos_token = @current_pos
    @sale.store = @current_pos.store
    @sale.user = @current_pos.store.user

    ActiveRecord::Base.transaction do
      if @sale.save
        save_sale_details
        save_sale_payments(payments)

        # Saleモデルのコールバックで pos_token.next_receipt_sequence がインクリメントされているため、
        # 最新の状態をリロードして取得し、クライアントへ返す（オフライン会計用）
        next_sequence = @current_pos.reload.next_receipt_sequence

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
  rescue => e
    logger.error "💥 エラー発生: #{e.class} - #{e.message}"
    logger.error e.backtrace.take(5).join("\n") unless Rails.env.production?
    render json: { success: false, errors: ['Internal Server Error'] }, status: :internal_server_error
  end

  private

  def sale_params
    # receipt_numberはオフライン同期時にクライアントから送られてくる場合がある
    params.require(:sale).permit(:total_amount, :payment_method, :receipt_number, :subtotal_ex_tax, :tax_amount)
  end

  def operator_employee
    return @operator_employee if defined?(@operator_employee)
    employee_id = params[:employee_id].presence
    @operator_employee = employee_id ? @current_pos.store.user.employees.find_by(id: employee_id) : nil
  end

  # 支払い明細（複数）のパラメータを配列として取得
  # 例: payments: [{ method: 0, amount: 500 }, { method: 1, amount: 500 }]
  def payment_params_array
    raw = params[:payments]
    return [] unless raw.is_a?(Array)

    raw.map do |p|
      attrs =
        if p.respond_to?(:permit)
          p.permit(:method, :amount)
        else
          p
        end

      {
        method: attrs[:method].to_i,
        amount: attrs[:amount].to_i
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

  def save_sale_details
    details = params[:details]
    return unless details.is_a?(Array)

    details.each do |detail|
      attrs = detail.respond_to?(:permit) ?
        detail.permit(:product_id, :product_name, :product_code, :quantity, :unit_price, :subtotal, :tax_rate, :tax_amount, :bundle_code) :
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

      # tax_rate: クライアント送信値を優先、なければ商品マスタから取得
      tax_rate = attrs[:tax_rate].present? ? attrs[:tax_rate].to_i : product.tax_rate
      unit_price = attrs[:unit_price].to_i
      quantity = attrs[:quantity].to_i
      subtotal = attrs[:subtotal].present? ? attrs[:subtotal].to_i : unit_price * quantity
      subtotal_ex_tax = (subtotal * 100 / (100 + tax_rate)).floor
      tax_amount = subtotal - subtotal_ex_tax

      sale_detail = @sale.saledetails.create!(
        product_id: product.id,
        product_name: attrs[:product_name].presence || product.name,
        quantity: quantity,
        unit_price: unit_price,
        subtotal: subtotal,
        tax_rate: tax_rate,
        tax_amount: tax_amount
      )

      deduct_stock(@sale.store, product, sale_detail.quantity, operator_employee)
    end
  end

  # セット商品を構成商品に展開して売上明細を作成する
  def save_bundle_detail(bundle_code, attrs)
    bundle = @sale.user.product_bundles.includes(product_bundle_items: :product).find_by(code: bundle_code)
    return unless bundle

    bundle_qty = attrs[:quantity].to_i
    bundle_qty = 1 if bundle_qty <= 0

    bundle.product_bundle_items.each do |item|
      product = item.product
      next unless product

      item_qty = item.quantity * bundle_qty
      unit_price = product.price
      subtotal = unit_price * item_qty
      tax_rate = product.tax_rate
      subtotal_ex_tax = (subtotal * 100 / (100 + tax_rate)).floor
      tax_amount = subtotal - subtotal_ex_tax

      @sale.saledetails.create!(
        product_id: product.id,
        product_name: product.name,
        quantity: item_qty,
        unit_price: unit_price,
        subtotal: subtotal,
        tax_rate: tax_rate,
        tax_amount: tax_amount
      )

      deduct_stock(@sale.store, product, item_qty, operator_employee)
    end
  end

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
          amount: p[:amount]
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