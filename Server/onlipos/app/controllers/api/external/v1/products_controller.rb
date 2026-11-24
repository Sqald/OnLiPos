class Api::External::V1::ProductsController < Api::External::V1::BaseController
  before_action(only: [ :index, :show ]) { require_scope!("products:read") }
  before_action(only: [ :create, :update ]) { require_scope!("products:write") }

  # 列挙値（status / tax_type）が不正な場合
  rescue_from(ArgumentError) { |e| render json: { error: "invalid", messages: [ e.message ] }, status: :unprocessable_entity }

  FIELDS = %i[code name price description status tax_rate tax_type cost_price eat_in_tax_rate eat_in_price min_age low_stock_threshold
              variant_group variant_name sold_by_weight track_stock].freeze

  def index
    page = paginate(account.products.includes(:product_category))
    render json: { products: page[:records].map { |p| product_json(p) }, next_after_id: page[:next_after_id] }
  end

  def show = render(json: { product: product_json(account.products.find(params[:id])) })

  def create = save(account.products.build(product_params), :created)

  def update
    product = account.products.find(params[:id])
    product.assign_attributes(product_params)
    save(product, :ok)
  end

  private

  def save(product, status)
    if product.save
      render json: { product: product_json(product) }, status: status
    else
      render json: { error: "invalid", messages: product.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def product_params = params.require(:product).permit(*FIELDS)

  def product_json(product)
    product.slice(:id, *FIELDS).merge(category: product.product_category&.name, updated_at: product.updated_at.iso8601)
  end
end
