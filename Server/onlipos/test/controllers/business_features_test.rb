require "test_helper"

# 税率変更の予約・店内飲食・オプション・年齢確認・自動値引き・クーポン・会員・仕入・棚卸・勤怠・セルフ注文・外部API など
class BusinessFeaturesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  BROWSER = { "User-Agent" => "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140.0.0.0 Safari/537.36" }.freeze

  setup do
    @user = User.create!(login_name: "bizowner", email: "biz@example.com", password: "Password1!", password_confirmation: "Password1!",
                         first_name: "a", last_name: "b", user_type: :individual, confirmed_at: Time.current)
    @store = @user.stores.create!(name: "S1", ascii_name: "storeone")
    @pos = @store.pos_tokens.create!(name: "P1", ascii_name: "pos1", password: "x", password_confirmation: "x")
    @emp = @user.employees.create!(code: "E1", name: "E1", pin: "1234")
    @emp2 = @user.employees.create!(code: "E2", name: "E2", pin: "1234")
    [ @emp, @emp2 ].each { |e| e.stores << @store; %w[refund inventory open_register].each { |p| e.employee_permissions.create!(permission: p) } }
    @food = @user.products.create!(code: "F", name: "弁当", price: 1080, tax_rate: 8, eat_in_tax_rate: 10, eat_in_price: 1100, cost_price: 400)
    @auth = { "Authorization" => "Bearer #{@pos.token}" }
  end

  def line(product, unit: product.price, quantity: 1, rate: product.tax_rate, **extra)
    { product_id: product.id, quantity: quantity, unit_price: unit, subtotal: unit * quantity, tax_rate: rate }.merge(extra)
  end

  def sell(lines, total, payments: nil, sale: {}, **extra)
    post "/api/v1/sales", params: { employee_id: @emp.id, sale: { total_amount: total }.merge(sale), details: lines,
                                    payments: payments || [ { method: 0, amount: total } ] }.merge(extra), headers: @auth, as: :json
    Sale.find_by(id: response.parsed_body["sale_id"])
  end

  def refund(sale, quantity = 1)
    post "/api/v1/refunds", params: { receipt_number: sale.receipt_number, employee_ids: [ @emp.id, @emp2.id ],
                                      details: [ { saledetail_id: sale.saledetails.first.id, quantity: quantity } ] }, headers: @auth, as: :json
    assert_response :created
  end

  # ── 税率変更 ──
  test "税率の予約変更は適用日の0時から有効になり、旧税率の会計は拒否され、返品は旧税率で計算される" do
    travel_to Time.zone.local(2027, 3, 31, 23, 50)
    old_sale = sell([ line(@food) ], 1080)
    assert_response :created
    TaxRateChangePlanner.new(@user, from_rate: 8, to_rate: 1, keep: "ex_tax").schedule!(effective_on: Date.new(2027, 4, 1))

    post "/api/v1/products/sync", params: { last_id: 0 }, headers: @auth, as: :json
    change = response.parsed_body["scheduled_changes"].first
    assert_equal [ 1, 1010, "2027-04-01" ], change.values_at("tax_rate", "price", "effective_on")
    sell([ line(@food, unit: 1010, rate: 1) ], 1010)
    assert_response :conflict, "適用日前に新税率では売れない"

    travel_to Time.zone.local(2027, 4, 1, 0, 1)
    sell([ line(@food) ], 1080)
    assert_response :conflict
    assert_equal "master_outdated", response.parsed_body["code"]
    sale = sell([ line(@food, unit: 1010, rate: 1) ], 1010)
    assert_response :created
    assert_equal [ 1, 10 ], sale.sale_tax_breakdowns.first.then { |b| [ b.tax_rate, b.tax_amount ] }

    # 店内飲食の税率は変わらない
    sell([ line(@food.reload, unit: 1100, rate: 10, service_type: "eat_in") ], 1100)
    assert_response :created

    refund(old_sale)
    assert_equal 8, Refund.last.refund_tax_breakdowns.first.tax_rate

    # 適用日前にオフラインで販売した会計は、旧税率のまま要確認なしで登録できる
    offline = sell([ line(@food, unit: 1080, rate: 8) ], 1080, sale: { receipt_number: "bizowner-storeone-#{@pos.id}-00000050", sold_at: "2027-03-31T23:55:00+09:00" })
    assert_response :created
    assert_empty offline.review_reasons
  end

  test "税込価格を維持する変更・カテゴリの除外・店舗価格の換算" do
    category = @user.product_categories.create!(name: "酒")
    @user.products.create!(code: "S", name: "除外", price: 1080, tax_rate: 8, product_category: category)
    Price.create!(store: @store, product: @food, amount: 540)
    rows = TaxRateChangePlanner.new(@user, from_rate: 8, to_rate: 1, keep: "ex_tax", excluded_category_ids: [ category.id ]).rows
    assert_equal [ [ 1080, 1010 ], [ 540, 505 ] ], rows.map { |r| [ r.current_price, r.new_price ] }
    assert_equal [ 1080 ], TaxRateChangePlanner.new(@user, from_rate: 8, to_rate: 1, keep: "in_tax").rows.reject(&:store).map(&:new_price).uniq
  end

  test "店内飲食と持ち帰りで税率・価格が変わる" do
    sale = sell([ line(@food), line(@food, unit: 1100, rate: 10, service_type: "eat_in") ], 2180)
    assert_response :created
    assert_equal [ 8, 10 ], sale.sale_tax_breakdowns.order(:tax_rate).map(&:tax_rate)
    assert_equal 400, sale.saledetails.first.cost_price
    sell([ line(@food, unit: 1080, rate: 10) ], 1080)
    assert_response :conflict, "持ち帰りに店内の税率は使えない"
  end

  # ── 商品 ──
  test "オプション料金と選択数を検証する" do
    group = @user.option_groups.create!(name: "トッピング", min_select: 1, max_select: 2, option_items_attributes: [ { name: "卵", price: 50 }, { name: "のり", price: 30 }, { name: "ねぎ", price: 0 } ])
    @food.option_groups << group
    egg, nori, negi = group.option_items.to_a
    sell([ line(@food) ], 1080)
    assert_response :unprocessable_entity
    sell([ line(@food, unit: 1080, options: [ egg.id ]) ], 1080)
    assert_response :forbidden, "オプション料金を含まない"
    sale = sell([ line(@food, unit: 1160, options: [ egg.id, nori.id ]) ], 1160)
    assert_equal %w[卵 のり], sale.saledetails.first.options.map { |o| o["name"] }
    sell([ line(@food, unit: 1160, options: [ egg.id, nori.id, negi.id ]) ], 1160)
    assert_response :unprocessable_entity
  end

  test "年齢確認が必要な商品" do
    sake = @user.products.create!(code: "SAKE", name: "酒", price: 500, min_age: 20)
    sell([ line(sake) ], 500)
    assert_equal "age_verification_required", response.parsed_body["code"]
    assert sell([ line(sake) ], 500, age_verified: true).age_verified
  end

  test "CSVの出力と取込（Shift_JIS・税区分・カテゴリ）" do
    csv = "code,name,price,tax_type,category,cost_price\nX1,外税商品,100,exclusive,新カテゴリ,40\nF,弁当2,1200,,,\nBAD,不正,100,unknown,,\n"
    sign_in @user
    file = Rack::Test::UploadedFile.new(StringIO.new(csv.encode("Windows-31J")), "text/csv", original_filename: "p.csv")
    perform_enqueued_jobs { post import_dashboard_products_path, params: { file: file } }
    import = @user.product_imports.last
    assert import.completed?, import.error_messages.inspect
    assert_nil import.content
    product = @user.products.find_by!(code: "X1")
    assert_equal [ "exclusive", "新カテゴリ", 40 ], [ product.tax_type, product.product_category.name, product.cost_price ]
    assert_equal [ 1200, 8 ], @food.reload.then { |p| [ p.price, p.tax_rate ] }
    assert_match "4行目", import.error_messages.first
    get export_dashboard_products_path
    assert_match "外税商品", response.body
  end

  test "商品画像の登録と端末からの取得" do
    sign_in @user
    png = Rack::Test::UploadedFile.new(StringIO.new(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")), "image/png", original_filename: "a.png")
    patch dashboard_product_path(@food), params: { product: { image: png } }
    assert @food.reload.image.attached?
    get "/api/v1/products/#{@food.id}/image", headers: @auth
    assert_equal "image/png", response.media_type
    svg = Rack::Test::UploadedFile.new(StringIO.new("<svg xmlns='http://www.w3.org/2000/svg'><script>1</script></svg>"), "image/svg+xml", original_filename: "a.svg")
    patch dashboard_product_path(@food), params: { product: { image: svg } }
    assert_response :unprocessable_entity
  end

  # ── 販売促進 ──
  test "タイムセールは値引き権限なしで売れ、時間外は売れない" do
    @user.promotions.create!(name: "夕市", kind: :time_sale, percent_off: 20, products: [ @food ], start_minute: 17 * 60, end_minute: 19 * 60)
    travel_to Time.zone.local(2026, 12, 1, 18, 0)
    sale = sell([ line(@food, unit: 864) ], 864)
    assert_response :created
    assert_equal [ 216, "夕市" ], [ sale.total_discount, sale.saledetails.first.promotion_name ]
    travel_to Time.zone.local(2026, 12, 1, 20, 0)
    sell([ line(@food, unit: 864) ], 864)
    assert_response :forbidden
  end

  test "よりどり・まとめ買い割引をサーバーで再計算する" do
    tea = @user.products.create!(code: "T", name: "茶", price: 150, tax_rate: 8)
    @user.promotions.create!(name: "2点1500円", kind: :set_price, set_quantity: 2, fixed_price: 1100, products: [ @food, tea ])
    sell([ line(@food), line(tea, quantity: 2) ], 1380, sale: { promotion_discount_total: 500 })
    assert_response :conflict
    sale = sell([ line(@food), line(tea, quantity: 2) ], 1250, sale: { promotion_discount_total: 130 })
    assert_response :created, response.body
    assert_equal [ 1250, 130 ], [ sale.saledetails.sum(:subtotal), sale.promotion_discount_total ]
  end

  test "クーポンの利用と上限・取消での復元" do
    coupon = @user.coupons.create!(code: "off100", name: "100円引き", discount_value: 100, min_total: 500, usage_limit: 1)
    post "/api/v1/pos_devices/open", params: { employee_id: @emp.id, open_date: Date.current.to_s, cash_drawer: %w[10000 5000 1000 500 100 50 10 5 1].to_h { |k| [ k, 0 ] } }, headers: @auth, as: :json
    get "/api/v1/coupons/OFF100?total=1080", headers: @auth
    assert_equal 100, response.parsed_body.dig("coupon", "discount")
    sale = sell([ line(@food) ], 980, sale: { coupon_code: "off100" })
    assert_response :created, response.body
    sell([ line(@food) ], 980, sale: { coupon_code: "OFF100" })
    assert_equal "coupon_invalid", response.parsed_body["code"]
    assert_equal 1, Sale.count
    post "/api/v1/sales/#{sale.id}/void", params: { employee_ids: [ @emp.id, @emp2.id ], reason: "x" }, headers: @auth, as: :json
    assert_response :ok
    assert_equal 0, coupon.reload.used_count
  end

  test "ポイントの付与・利用・返品での取消と、掛売" do
    @user.update!(point_yen_per_point: 100)
    customer = @user.customers.create!(name: "会員", phone: "0312345678")
    sale = sell([ line(@food) ], 1080, customer_code: customer.code)
    assert_equal 10, customer.reload.points
    assert_equal 10, response.parsed_body["points_balance"]

    sell([ line(@food) ], 1080, customer_code: customer.code, payments: [ { method: 4, amount: 1080 } ])
    assert_response :unprocessable_entity, "残高不足"
    customer.add_points!(490, kind: :adjusted)
    paid = sell([ line(@food) ], 1080, customer_code: customer.code, payments: [ { method: 4, amount: 500 }, { method: 0, amount: 580 } ])
    assert_equal 5, customer.reload.points
    refund(paid)
    assert_equal 500, customer.reload.points, "利用分が戻り、付与分が取り消される"
    refund(sale)
    assert_equal 490, customer.reload.points
    assert_raises(Customer::InsufficientPoints) { customer.add_points!(-1000, kind: :used) }

    sell([ line(@food) ], 1080, customer_code: customer.code, payments: [ { method: 6, amount: 1080 } ])
    assert_response :unprocessable_entity
    customer.update!(credit_allowed: true)
    sell([ line(@food) ], 1080, customer_code: customer.code, payments: [ { method: 6, amount: 1080 } ])
    assert_equal 1080, customer.reload.receivable
    get "/api/v1/customers?q=0312345678", headers: @auth
    assert_equal customer.code, response.parsed_body["customers"].first["code"]
    get "/api/v1/customers?q=abc", headers: @auth
    assert_response :bad_request
  end

  # ── 仕入・在庫・勤怠 ──
  test "発注から入荷、在庫と原価の更新、在庫不足の通知" do
    @food.update!(low_stock_threshold: 5)
    supplier = @user.suppliers.create!(name: "仕入先")
    order = @user.purchase_orders.create!(store: @store, supplier: supplier, items_attributes: [ { product_id: @food.id, quantity: 10, unit_cost: 450 } ])
    order.place!
    item = order.items.first
    post "/api/v1/purchase_orders/#{order.id}/receive", params: { employee_id: @emp.id, received: { item.id => 6 } }, headers: @auth, as: :json
    assert_response :ok
    assert order.reload.partially_received?
    assert_equal [ 6, 450 ], [ StoreStock.find_by(product: @food).quantity, @food.reload.cost_price ]
    post "/api/v1/purchase_orders/#{order.id}/receive", params: { employee_id: @emp.id, received: { item.id => 5 } }, headers: @auth, as: :json
    assert_response :unprocessable_entity

    Webhook.create!(user: @user, url: "https://example.com/hook", events: [ "stock.low" ])
    assert_enqueued_jobs(1, only: WebhookDeliveryJob) { sell([ line(@food) ], 1080); sell([ line(@food) ], 1080) }
  end

  test "棚卸の登録と確定" do
    StoreStock.adjust!(store: @store, product: @food, change: 10, reason: "manual_in")
    stocktake = @user.stocktakes.create!(store: @store, name: "棚卸")
    post "/api/v1/stocktakes/#{stocktake.id}/count", params: { employee_id: @emp.id, jan_code: "F", quantity: 4 }, headers: @auth, as: :json
    post "/api/v1/stocktakes/#{stocktake.id}/count", params: { employee_id: @emp.id, jan_code: "F", quantity: 3, add: true }, headers: @auth, as: :json
    assert_equal 7, response.parsed_body["counted_quantity"]
    stocktake.complete!(by: "x")
    assert_equal 7, StoreStock.find_by(product: @food).quantity
    assert_equal(-3, StockMovement.where(reason: "stocktake").last.quantity_change)
  end

  test "勤怠の打刻にはPINが必要" do
    post "/api/v1/attendances", params: { code: "E1", pin: "0000", punch: "clock_in" }, headers: @auth, as: :json
    assert_response :unauthorized
    travel_to Time.zone.local(2026, 12, 1, 9, 0)
    post "/api/v1/attendances", params: { code: "E1", pin: "1234", punch: "clock_in" }, headers: @auth, as: :json
    assert_response :created
    post "/api/v1/attendances", params: { code: "E1", pin: "1234", punch: "clock_in" }, headers: @auth, as: :json
    assert_response :unprocessable_entity
    travel 4.hours
    post "/api/v1/attendances", params: { code: "E1", pin: "1234", punch: "break_start" }, headers: @auth, as: :json
    travel 1.hour
    post "/api/v1/attendances", params: { code: "E1", pin: "1234", punch: "clock_out" }, headers: @auth, as: :json
    assert_equal [ 60, 240 ], response.parsed_body.values_at("break_minutes", "worked_minutes")
  end

  test "予約の重複を防ぐ" do
    start = 1.day.from_now
    @store.reservations.create!(name: "A", starts_at: start, table_number: "1")
    assert_not @store.reservations.build(name: "B", starts_at: start + 1.hour, table_number: "1").valid?
    assert @store.reservations.build(name: "B", starts_at: start + 3.hours, table_number: "1").valid?
  end

  # ── 店舗運営 ──
  test "転送・卓・保留のカートは端末の形式のまま受け渡せる" do
    item = { product: { id: @food.id, name: "弁当" }, quantity: 2, override_price: nil, weight_grams: 500 }
    post "/api/v1/transfer_orders", params: { transfer_order: { operator_name: "a", operator_id: 1, total_amount: 1, items: [ item ] } }, headers: @auth, as: :json
    assert_response :created
    delete "/api/v1/transfer_orders/#{response.parsed_body["id"]}", headers: @auth
    assert_equal [ @food.id, 500 ], response.parsed_body["transfer_order"]["items"].first.then { |i| [ i["product"]["id"], i["weight_grams"] ] }

    post "/api/v1/hold_orders", params: { operator_name: "a", operator_id: 1, total_amount: 1, items: [ item ] }, headers: @auth, as: :json
    number = response.parsed_body["hold_number"]
    delete "/api/v1/hold_orders/#{number}", headers: @auth
    assert_equal 1, response.parsed_body["items"].size
    delete "/api/v1/hold_orders/#{number}", headers: @auth
    assert_response :not_found
  end

  test "セルフ注文は卓の注文と厨房に届き、金額はサーバーで決まる" do
    code = @store.table_codes.create!(table_number: "5")
    get self_order_path(code.token)
    assert_response :not_found, "受付していない"
    @store.update!(self_order_enabled: true)
    @user.products.create!(code: "SAKE", name: "酒", price: 500, min_age: 20)
    get self_order_path(code.token)
    assert_match "弁当", response.body
    assert_no_match "酒", response.body

    request_id = SecureRandom.uuid
    2.times { post self_order_path(code.token), params: { request_id: request_id, items: { @food.id => { quantity: 2, price: 1 } } } }
    assert_equal 1, KitchenOrder.count
    get "/api/v1/table_orders/5", headers: @auth
    cart = response.parsed_body["items"]
    assert_equal [ 1, 2, 1080, true ], [ cart.size, cart[0]["quantity"], cart[0]["product"]["price"], cart[0]["eat_in"] ]

    @store.rotate_kitchen_display_token!
    get kitchen_path(@store.kitchen_display_token)
    assert_match "弁当", response.body
    post kitchen_advance_path(@store.kitchen_display_token, KitchenOrder.last)
    assert KitchenOrder.last.accepted?
    get kitchen_path("wrong")
    assert_response :not_found
  end

  test "客用表示と電子レシート" do
    put "/api/v1/customer_display", params: { items: [ { name: "弁当", quantity: 1, subtotal: 1080 } ], total: 1080 }, headers: @auth, as: :json
    get customer_display_page_path(CustomerDisplay.last.token)
    assert_match "¥1,080", response.body

    sale = sell([ line(@food) ], 1080)
    get URI.parse(response.parsed_body["receipt_url"]).path
    assert_response :ok
    assert_match sale.receipt_number, response.body
    assert_no_match "E1", response.body
    @user.update!(digital_receipt_enabled: false)
    get digital_receipt_full_path(sale.public_token)
    assert_response :not_found
  end

  # ── 外部連携 ──
  test "外部APIはキーの権限と契約の範囲で動く" do
    sale = sell([ line(@food) ], 1080)
    key = @user.api_keys.create!(name: "連携", scopes: [ "sales:read", "products:write" ])
    headers = { "Authorization" => "Bearer #{key.token}" }
    get "/api/external/v1/sales", headers: headers
    assert_equal sale.receipt_number, response.parsed_body["sales"].first["receipt_number"]
    get "/api/external/v1/stocks", headers: headers
    assert_response :forbidden
    post "/api/external/v1/products", params: { product: { code: "EXT", name: "外部", price: 1, user_id: 0 } }, headers: headers, as: :json
    assert_equal @user, Product.find_by(code: "EXT").user
    post "/api/external/v1/products", params: { product: { code: "EXT2", name: "外部", price: 1, status: "zzz" } }, headers: headers, as: :json
    assert_response :unprocessable_entity
    key.revoke!
    get "/api/external/v1/sales", headers: headers
    assert_response :unauthorized
  end

  test "Webhookは内部アドレスへ送信せず、署名を付ける" do
    assert_not Webhook.new(user: @user, url: "http://example.com", events: [ "sale.created" ]).valid?
    %w[127.0.0.1 10.1.2.3 169.254.169.254 ::1 ::ffff:127.0.0.1 fd00::1].each { |ip| assert_not Webhook.public_address?(IPAddr.new(ip)), ip }
    assert Webhook.public_address?(IPAddr.new("93.184.216.34"))
    hook = Webhook.create!(user: @user, url: "https://localhost/x", events: [ "sale.created" ])
    assert_no_match hook.secret, hook.secret_ciphertext
    perform_enqueued_jobs(only: WebhookDeliveryJob) { WebhookDeliveryJob.perform_later(hook.id, "sale.created", {}) } rescue nil
    assert_match "内部アドレス", hook.reload.last_error
  end

  test "仕訳データは売上・返品と一致する" do
    sale = sell([ line(@food), line(@food, unit: 1100, rate: 10, service_type: "eat_in") ], 2180, payments: [ { method: 0, amount: 1000 }, { method: 1, amount: 1180 } ])
    refund(sale)
    export = AccountingExport.new(@user, from: Date.current, to: Date.current, store_ids: [ @store.id ])
    sales_total = export.entries.select { |e| e.credit == "売上高" }.sum(&:amount)
    refund_total = export.entries.select { |e| e.debit == "売上高" }.sum(&:amount)
    assert_equal [ 2180, 1080 ], [ sales_total, refund_total ]
    AccountingExport::FORMATS.each_key { |format| assert export.to_file(format).first.bytesize.positive? }
    assert_equal Encoding::Windows_31J, export.yayoi_csv.encoding
  end

  test "粗利を集計し、返品分を差し引く" do
    sale = sell([ line(@food, quantity: 2) ], 2160)
    profit = -> { SalesAnalysis.new(user: @user, from: Date.current, to: Date.current, row_dim: "product", metric: "profit").then { |a| a.respond_to?(:grand_total) ? a.grand_total.profit : a.rows.first.total.profit } }
    assert_equal 2000 - 800, profit.call
    refund(sale)
    assert_equal 1000 - 400, profit.call
  end

  test "業務機能の全画面が表示でき、登録できる" do
    sign_in @user
    post dashboard_reauthentication_path, params: { password: "Password1!" }
    customer = @user.customers.create!(name: "会員")
    supplier = @user.suppliers.create!(name: "仕入先")
    order = @user.purchase_orders.create!(store: @store, supplier: supplier, items_attributes: [ { product_id: @food.id, quantity: 1, unit_cost: 1 } ])
    stocktake = @user.stocktakes.create!(store: @store, name: "棚卸")
    stocktake.count!(@food, 1)
    Attendance.punch!("clock_in", employee: @emp, store: @store, pos_token: @pos)
    group = @user.option_groups.create!(name: "g", option_items_attributes: [ { name: "i", price: 1 } ])
    @store.table_codes.create!(table_number: "1")
    @store.rotate_kitchen_display_token!
    @user.api_keys.create!(name: "k", scopes: [ "sales:read" ])
    Webhook.create!(user: @user, url: "https://example.com", events: [ "sale.created" ])
    @user.scheduled_product_changes.create!(product: @food, effective_on: 1.day.from_now, price: 1)
    @user.coupons.create!(code: "ABC", name: "c", discount_value: 1)
    @user.promotions.create!(name: "p", kind: :time_sale, percent_off: 1, products: [ @food ])
    @store.reservations.create!(name: "r", starts_at: 1.hour.from_now)
    @food.update!(low_stock_threshold: 100)
    StoreStock.adjust!(store: @store, product: @food, change: 1, reason: "manual_in")

    paths = [ dashboard_option_groups_path, new_dashboard_option_group_path, edit_dashboard_option_group_path(group), dashboard_scheduled_changes_path,
              tax_change_dashboard_scheduled_changes_path(effective_on: 2.days.from_now.to_date, from_rate: 8, to_rate: 1, keep: "ex_tax"),
              dashboard_coupons_path, new_dashboard_coupon_path, dashboard_promotions_path, new_dashboard_promotion_path, edit_dashboard_promotion_path(@user.promotions.first),
              dashboard_customers_path, new_dashboard_customer_path, dashboard_customer_path(customer), edit_dashboard_customer_path(customer),
              dashboard_suppliers_path, new_dashboard_supplier_path, dashboard_purchase_orders_path, dashboard_purchase_order_path(order),
              new_dashboard_purchase_order_path(store_id: @store.id, supplier_id: supplier.id), edit_dashboard_purchase_order_path(order),
              dashboard_stocktakes_path, dashboard_stocktake_path(stocktake), dashboard_stocktake_path(stocktake, format: :csv), dashboard_low_stocks_path,
              dashboard_attendances_path, dashboard_attendances_path(format: :csv), dashboard_reservations_path, new_dashboard_reservation_path,
              dashboard_table_codes_path, dashboard_accounting_export_path, dashboard_accounting_export_path(export: "freee"), dashboard_api_keys_path,
              dashboard_webhooks_path, new_dashboard_webhook_path, dashboard_products_path, edit_dashboard_product_path(@food), new_dashboard_product_path ]
    paths.each do |path|
      get path, headers: BROWSER
      assert_response :ok, path
    end

    other = User.create!(login_name: "otherbiz", email: "o@example.com", password: "Password1!", password_confirmation: "Password1!", first_name: "a", last_name: "b", user_type: :individual, confirmed_at: Time.current)
    other_category = other.product_categories.create!(name: "他社")
    post dashboard_promotions_path, params: { promotion: { name: "x", kind: "time_sale", percent_off: 10, product_category_id: other_category.id } }
    assert_response :unprocessable_entity
    post dashboard_promotions_path, params: { promotion: { name: "朝", kind: "time_sale", percent_off: 10, product_ids: [ "", @food.id ], start_time: "07:00", end_time: "10:00", weekdays: [ "", "1" ], active: "1" } }
    assert_equal [ 420, [ 1 ] ], Promotion.last.then { |p| [ p.start_minute, p.weekdays ] }
    post apply_tax_change_dashboard_scheduled_changes_path, params: { effective_on: 2.days.from_now.to_date, from_rate: 8, to_rate: 1, keep: "ex_tax" }
    assert_equal 1, @user.scheduled_product_changes.where(tax_rate: 1).count
    get dashboard_customer_path(other.customers.create!(name: "他社会員")), headers: BROWSER
    assert_redirected_to dashboard_root_path
  end
end
