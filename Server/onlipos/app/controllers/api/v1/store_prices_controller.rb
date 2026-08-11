# 店舗別価格（本部の定価とは別に店舗ごとに上書きできる価格）の閲覧・更新API。
# edit_prices 権限を持つ従業員のみ利用可能。
class Api::V1::StorePricesController < Api::V1::BaseController
  PAGE_LIMIT = 50

  # GET /api/v1/store_prices?employee_id=&q=&last_id=
  def index
    store    = @current_pos.store
    employee = resolve_employee(store)
    return unless employee

    authorize_employee!(employee, "edit_prices")
    return if performed?

    last_id = (params[:last_id] || 0).to_i
    q       = params[:q].to_s.strip

    scope = store.products.where("products.id > ?", last_id).order(:id)
    if q.present?
      escaped = ActiveRecord::Base.sanitize_sql_like(q)
      scope = scope.where(
        "products.code LIKE :q OR products.name LIKE :q",
        q: "%#{escaped}%"
      )
    end
    products = scope.limit(PAGE_LIMIT)

    product_ids = products.map(&:id)
    prices      = Price.where(store_id: store.id, product_id: product_ids).index_by(&:product_id)

    has_more = products.length == PAGE_LIMIT
    next_id  = products.last&.id || last_id

    render json: {
      success:  true,
      has_more: has_more,
      last_id:  next_id,
      products: products.map { |p|
        {
          product_id:  p.id,
          code:        p.code,
          name:        p.name,
          list_price:  p.price,
          store_price: prices[p.id]&.amount
        }
      }
    }
  end

  # PATCH /api/v1/store_prices
  # body: { employee_id, product_id, mode: "list"|"store", amount? }
  def update
    store    = @current_pos.store
    employee = resolve_employee(store)
    return unless employee

    authorize_employee!(employee, "edit_prices")
    return if performed?

    product = store.products.find_by(id: params[:product_id])
    unless product
      return render json: { success: false, message: "商品が見つかりません" }, status: :not_found
    end

    case params[:mode]
    when "list"
      Price.where(store_id: store.id, product_id: product.id).destroy_all
      render json: { success: true, mode: "list" }

    when "store"
      raw_amount = params[:amount]
      if raw_amount.nil?
        return render json: { success: false, message: "amount が必要です" }, status: :unprocessable_entity
      end
      amount = raw_amount.to_i
      if amount < 0
        return render json: { success: false, message: "金額は0以上を指定してください" }, status: :unprocessable_entity
      end
      price = Price.find_or_initialize_by(store_id: store.id, product_id: product.id)
      price.amount = amount
      if price.save
        render json: { success: true, mode: "store", amount: price.amount }
      else
        render json: { success: false, message: price.errors.full_messages.join(", ") },
               status: :unprocessable_entity
      end

    else
      render json: { success: false, message: "mode は list または store を指定してください" },
             status: :bad_request
    end
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
end
