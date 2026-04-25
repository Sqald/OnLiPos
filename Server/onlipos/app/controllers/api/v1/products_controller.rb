class Api::V1::ProductsController < Api::V1::BaseController
  def lookup
    code = params[:code].to_s.strip
    return render json: { success: false, message: 'code is required' }, status: :bad_request if code.blank?

    current_store = @current_pos.store
    product = current_store.products.find_by(code: code, status: :active)

    if product.nil?
      return render json: { success: false, message: 'not_found' }, status: :not_found
    end

    price = Price.find_by(store_id: current_store.id, product_id: product.id)&.amount || product.price

    render json: {
      success: true,
      product: {
        id: product.id,
        code: product.code,
        name: product.name,
        price: price,
        tax_rate: product.tax_rate,
      }
    }, status: :ok
  end

  def sync
    limit = 1000
    
    # ストロングパラメータを使用
    last_updated_at_param = sync_params[:last_updated_at]
    last_updated_at = if last_updated_at_param.present?
                        Time.zone.parse(last_updated_at_param) || Time.at(0)
                      else
                        Time.at(0)
                      end
    last_id = (sync_params[:last_id] || 0).to_i

    # サーバーの「現在時刻」を取得（同期開始時にFlutterに教えるため）
    server_time = Time.current

    # 現在のPOS端末が所属する店舗を取得
    current_store = @current_pos.store

    # 「しおり」以降のデータを1000件取得する（updated_at順、同じ時刻ならid順）
    products = current_store.products
                            .where("(products.updated_at > ?) OR (products.updated_at = ? AND products.id > ?)", last_updated_at, last_updated_at, last_id)
                            .order(updated_at: :asc, id: :asc)
                            .limit(limit)

    # 取得した商品IDに対応する、この店舗の価格情報を取得
    product_ids = products.map(&:id)
    prices = Price.where(store_id: current_store.id, product_id: product_ids).index_by(&:product_id)

    # 1000件ピッタリ取れたら「まだ続きがある」と判定
    has_more = products.length == limit

    # 今回取得した最後のレコード情報を取得（次回リクエスト用）
    last_record = products.last
    next_updated_at = last_record ? last_record.updated_at : last_updated_at
    next_id = last_record ? last_record.id : last_id

    # レスポンス用データの作成
    response_products = products.map do |product|
      # 店舗ごとの価格設定があればそれを優先し、なければ基本価格を使用
      current_price = prices[product.id]&.amount || product.price

      {
        id: product.id,
        code: product.code,
        name: product.name,
        description: product.description,
        status: product.status,
        price: current_price,
        tax_rate: product.tax_rate,
        updated_at: product.updated_at
      }
    end

    # セット商品の同期（全件、カーソルなし）
    bundles = current_store.user.product_bundles
                           .includes(product_bundle_items: :product)
                           .where(status: :active)
    response_bundles = bundles.map do |bundle|
      {
        id: bundle.id,
        code: bundle.code,
        name: bundle.name,
        price: bundle.price,
        items: bundle.product_bundle_items.map do |item|
          {
            product_id: item.product_id,
            product_code: item.product&.code,
            quantity: item.quantity
          }
        end
      }
    end

    render json: {
      success: true,
      server_time: server_time, # 同期開始時の基準となる時刻
      has_more: has_more,
      last_updated_at: next_updated_at,
      last_id: next_id,
      products: response_products,
      bundles: response_bundles
    }, status: :ok
  end

  private

  def sync_params
    params.permit(:last_updated_at, :last_id)
  end
end