# セルフ注文。厨房への注文を登録し、レジの卓注文（会計前のカート）にも加える
class SelfOrder
  class Error < StandardError; end

  # 注文できる商品（有効・量り売りでない・年齢確認が不要）
  def self.menu(store)
    store.user.products.active.where(sold_by_weight: false, min_age: nil)
         .includes(:product_category, option_groups: :option_items).order(:product_category_id, :code)
  end

  def initialize(store, table_number)
    @store = store
    @table_number = table_number
  end

  # 二重送信は登録せず nil を返す
  def place!(items, request_id)
    raise Error, "商品を選んでください" if items.empty?

    request_id = request_id.to_s[/\A[0-9a-f-]{36}\z/] or raise Error, "もう一度お試しください"
    products = self.class.menu(@store).where(id: items.map { |i| i[:product_id] }).index_by(&:id)
    lines = items.map { |item| build_line(products[item[:product_id]], item) }

    KitchenOrder.transaction do
      order = @store.kitchen_orders.create!(table_number: @table_number, source: :self_order, client_request_id: request_id,
                                            items: lines.map { |l| l.slice("product_id", "name", "quantity", "options") })
      add_to_table(lines)
      order
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  private

  def build_line(product, item)
    raise Error, "選択された商品は現在注文できません" unless product

    available = product.option_groups.flat_map(&:option_items)
    options = available.select { |o| item[:option_ids].include?(o.id) }
    product.option_groups.each do |group|
      count = options.count { |o| o.option_group_id == group.id }
      raise Error, "#{product.name}: 「#{group.name}」は#{group.min_select}〜#{group.max_select}個選んでください" unless count.between?(group.min_select, group.max_select)
    end
    { "product_id" => product.id, "name" => product.name, "quantity" => item[:quantity], "options" => options.map(&:name),
      "option_ids" => options.map(&:id), "product" => product, "option_items" => options }
  end

  # レジの端末が読み込める形式（ScannedItem）で卓注文に加える
  def add_to_table(lines)
    @store.with_lock do
      table = @store.table_orders.find_or_initialize_by(table_number: @table_number)
      table.items = table.items.to_a + lines.map { |line| cart_item(line) }
      table.save!
    end
  end

  def cart_item(line)
    product = line["product"]
    price = Price.find_by(store_id: @store.id, product_id: product.id)&.amount || product.price
    {
      "product" => {
        "id" => product.id, "code" => product.code, "name" => product.name, "description" => product.description, "price" => price, "list_price" => product.price,
        "tax_rate" => product.tax_rate, "tax_type" => Product.tax_types[product.tax_type], "eat_in_tax_rate" => product.eat_in_tax_rate, "eat_in_price" => product.eat_in_price,
        "category_id" => product.product_category_id, "category_name" => product.product_category&.name, "sold_by_weight" => 0
      },
      "bundle_code" => nil, "bundle_name" => nil, "quantity" => line["quantity"], "override_price" => nil, "discount_reason" => nil, "weight_grams" => nil,
      "eat_in" => true, "options" => line["option_items"].map { |o| { "id" => o.id, "name" => o.name, "price" => o.price } }
    }
  end
end
