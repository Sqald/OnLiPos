require 'csv'

class Dashboard::SalesController < Dashboard::BaseController
  # 売上一覧は検索条件（店舗・期間）を指定して検索したときのみデータを取得する。
  # 自ユーザー（current_user）の売上のみに厳格にスコープする。
  def index
    @stores = current_user.stores.order(:name)
    @allowed_store_ids = current_user.stores.pluck(:id)

    unless search_performed?
      @sales = Sale.none.page(1).per(50)
      return
    end

    scope = build_scope

    respond_to do |format|
      format.html do
        @sales = scope
          .includes(:store, :pos_token, :sale_payments)
          .order(created_at: :desc)
          .page(params[:page])
          .per(50)
      end
      format.csv do
        sales_scope = scope.order(created_at: :desc)
        send_data generate_sales_csv(sales_scope),
                  filename: "sales_#{Date.current}.csv",
                  type: 'text/csv; charset=UTF-8'
      end
    end
  end

  private

  def build_scope
    scope = Sale.where(user_id: current_user.id)

    if params[:store_id].present? && @allowed_store_ids.include?(params[:store_id].to_i)
      scope = scope.where(store_id: params[:store_id])
    end

    if params[:from].present?
      from_time = begin
        Date.strptime(params[:from], '%Y-%m-%d').beginning_of_day
      rescue ArgumentError
        nil
      end
      scope = scope.where("created_at >= ?", from_time) if from_time
    end

    if params[:to].present?
      to_time = begin
        Date.strptime(params[:to], '%Y-%m-%d').end_of_day
      rescue ArgumentError
        nil
      end
      scope = scope.where("created_at <= ?", to_time) if to_time
    end

    scope
  end

  def generate_sales_csv(scope)
    payment_labels = { 'cash' => '現金', 'card' => 'カード', 'barcode' => 'バーコード決済' }
    output = StringIO.new
    output << "\xEF\xBB\xBF"
    csv = CSV.new(output)
    csv << ['日時', '店舗', 'POS端末', 'レシート番号', '支払方法', '金額（税込）', '税抜小計', '消費税']
    scope.includes(:store, :pos_token, :sale_payments).find_each(batch_size: 500) do |sale|
      payment_str = if sale.sale_payments.any?
        sale.sale_payments.map { |p| "#{payment_labels[p.method] || p.method}(#{p.amount}円)" }.join(' / ')
      else
        payment_labels[sale.payment_method] || sale.payment_method.to_s
      end
      csv << [
        sale.created_at.in_time_zone('Asia/Tokyo').strftime('%Y-%m-%d %H:%M:%S'),
        sale.store.name,
        sale.pos_token&.ascii_name || '-',
        sale.receipt_number,
        payment_str,
        sale.total_amount,
        sale.subtotal_ex_tax,
        sale.tax_amount
      ]
    end
    output.string
  end

  def search_performed?
    params[:store_id].present? || params[:from].present? || params[:to].present?
  end
end
