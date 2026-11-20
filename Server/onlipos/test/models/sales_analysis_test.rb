require "test_helper"

class SalesAnalysisTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "analysis", email: "analysis@example.com",
      password: "Password1!", password_confirmation: "Password1!",
      first_name: "太郎", last_name: "分析", user_type: :individual,
      confirmed_at: Time.current
    )
    @store_a = @user.stores.create!(name: "A店", ascii_name: "storea")
    @store_b = @user.stores.create!(name: "B店", ascii_name: "storeb")
    @pos_a = @store_a.pos_tokens.create!(name: "A-1", ascii_name: "posa1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @emp1 = @user.employees.create!(code: "E1", name: "山田")
    @emp2 = @user.employees.create!(code: "E2", name: "佐藤")
    @cat = ProductCategory.create!(user: @user, name: "飲料")
    @coffee = @user.products.create!(code: "C1", name: "コーヒー", price: 300, product_category: @cat)
    @cake = @user.products.create!(code: "K1", name: "ケーキ", price: 500)
    @day = Date.new(2026, 11, 10)

    # A店・山田: コーヒー2 + ケーキ1 = 1100円（現金）
    @s1 = make_sale(@store_a, @emp1, [ [ @coffee, 2, 300 ], [ @cake, 1, 500 ] ], pos: @pos_a, method: :cash)
    # A店・佐藤: コーヒー1 = 300円（カード）
    make_sale(@store_a, @emp2, [ [ @coffee, 1, 300 ] ], method: :card)
    # B店・山田: ケーキ2 = 1000円（翌日）
    make_sale(@store_b, @emp1, [ [ @cake, 2, 500 ] ], date: @day + 1)
    # 取消（VOID）は集計から除外される
    v = make_sale(@store_b, @emp2, [ [ @cake, 10, 500 ] ])
    v.update!(status: :voided, voided_at: Time.current, void_reason: "誤登録")
    # 他社の売上は混ざらない
    other = User.create!(login_name: "analysisx", email: "analysisx@example.com", password: "Password1!",
                         password_confirmation: "Password1!", first_name: "太郎", last_name: "他社",
                         user_type: :individual, confirmed_at: Time.current)
    ostore = other.stores.create!(name: "他社店", ascii_name: "otherx")
    oprod = other.products.create!(code: "C1", name: "他社コーヒー", price: 300)
    os = Sale.create!(user: other, store: ostore, total_amount: 9000, payment_method: :cash, business_date: @day)
    os.saledetails.create!(product: oprod, product_name: "他社コーヒー", quantity: 30, unit_price: 300, subtotal: 9000)
  end

  def make_sale(store, employee, lines, date: @day, pos: nil, method: :cash)
    total = lines.sum { |_, q, p| q * p }
    sale = Sale.create!(user: @user, store: store, employee: employee, pos_token: pos, total_amount: total,
                        payment_method: method, business_date: date, sold_at: date.in_time_zone.change(hour: 13))
    lines.each do |product, qty, price|
      sale.saledetails.create!(product: product, product_name: product.name, quantity: qty, unit_price: price,
                               subtotal: qty * price, tax_rate: 10)
    end
    sale
  end

  def analysis(**opts)
    SalesAnalysis.new(user: @user, from: @day, to: @day + 1, **opts)
  end

  def row_values(a, metric = "amount")
    a.rows.to_h { |r| [ r.label, r.total.value(metric) ] }
  end

  test "合計は取消・他社を除いた売上金額・点数・客数" do
    t = analysis.totals
    assert_equal 2400, t.amount
    assert_equal 6, t.quantity
    assert_equal 3, t.tickets
    assert_equal 800, t.value("avg_ticket")
  end

  test "店舗別・従業員別・商品別に集計できる" do
    assert_equal({ "A店" => 1400, "B店" => 1000 }, row_values(analysis(row_dim: "store")))
    assert_equal({ "山田（E1）" => 2100, "佐藤（E2）" => 300 }, row_values(analysis(row_dim: "employee")))
    products = analysis(row_dim: "product")
    assert_equal({ "ケーキ（K1）" => 1500, "コーヒー（C1）" => 900 }, row_values(products))
    assert_equal({ "ケーキ（K1）" => 3, "コーヒー（C1）" => 3 }, row_values(products, "quantity"))
  end

  test "日別は期間内を欠番なく並べ、カテゴリ未設定は未分類になる" do
    assert_equal [ "2026-11-10(火)", "2026-11-11(水)" ], analysis(row_dim: "day").rows.map(&:label)
    assert_equal({ "飲料" => 900, "未分類" => 1500 }, row_values(analysis(row_dim: "category")))
  end

  test "時間帯・支払方法・単価帯で集計できる" do
    assert_equal({ "13時台" => 2400 }, row_values(analysis(row_dim: "hour")))
    assert_equal({ "現金" => 2100, "カード" => 300 }, row_values(analysis(row_dim: "payment")))
    assert_equal({ "300〜499円" => 900, "500〜999円" => 1500 }, row_values(analysis(row_dim: "price_band")))
  end

  test "クロス集計（従業員×商品）のセル・列合計が正しい" do
    a = analysis(row_dim: "employee", col_dim: "product", metric: "quantity")
    yamada = a.rows.find { |r| r.label.start_with?("山田") }
    cells = a.columns.to_h { |k, label| [ label, yamada.cells[k].quantity ] }
    assert_equal({ "ケーキ（K1）" => 3, "コーヒー（C1）" => 2 }, cells)
    col_totals = a.columns.to_h { |k, label| [ label, a.column_totals[k].quantity ] }
    assert_equal({ "ケーキ（K1）" => 3, "コーヒー（C1）" => 3 }, col_totals)
  end

  test "客数は商品をまたいでも重複計上しない" do
    a = analysis(row_dim: "product", metric: "tickets")
    assert_equal 3, a.totals.tickets
    assert_equal 4, a.rows.sum { |r| r.total.tickets } # 1会計に2商品 → 行ごとには重複する
  end

  test "絞り込み（店舗・従業員・商品）" do
    assert_equal 1400, analysis(filters: { store_id: @store_a.id }).totals.amount
    assert_equal 2100, analysis(filters: { employee_id: @emp1.id }).totals.amount
    assert_equal 900, analysis(filters: { product_id: @coffee.id }).totals.amount
    assert_equal 1100, analysis(filters: { pos_token_id: @pos_a.id }).totals.amount
  end

  test "返品は返品日にマイナス計上され、元の担当者・商品に帰属する" do
    sd = @s1.saledetails.find_by(product: @cake)
    refund = Refund.create!(sale: @s1, store: @store_b, user: @user, employee: @emp2, total_amount: 500,
                            business_date: @day + 1, refunded_at: (@day + 1).in_time_zone.change(hour: 10))
    refund.refund_details.create!(saledetail: sd, product: @cake, product_name: "ケーキ", quantity: 1,
                                  unit_price: 500, subtotal: 500)

    a = analysis(row_dim: "employee")
    assert_equal 1900, a.totals.amount
    assert_equal 500, a.totals.refund_amount
    assert_equal 2400, a.totals.gross_amount
    assert_equal({ "山田（E1）" => 1600, "佐藤（E2）" => 300 }, row_values(a))
    assert_equal({ "A店" => 1400, "B店" => 500 }, row_values(analysis(row_dim: "store")))
    assert_equal 2400, analysis(include_refunds: false).totals.amount
  end

  test "表示件数を超えた分類は「その他」にまとまり、合計は保たれる" do
    a = analysis(row_dim: "product", row_limit: 1)
    # row_limit は最低 5 に丸められるため、ここでは2商品すべてが表示される
    assert_equal 2, a.rows.size

    5.times do |i|
      p = @user.products.create!(code: "X#{i}", name: "商品#{i}", price: 100)
      make_sale(@store_a, @emp1, [ [ p, 1, 100 ] ])
    end
    a = analysis(row_dim: "product", row_limit: 5)
    assert_equal 6, a.rows.size
    other = a.rows.last
    assert_equal SalesAnalysis::OTHER_KEY, other.key
    assert_equal a.totals.amount, a.rows.sum { |r| r.total.amount }
  end

  test "不正な軸・指標は既定値に戻る" do
    a = analysis(row_dim: "users; DROP TABLE sales", col_dim: "x", metric: "y")
    assert_equal "day", a.row_dim
    assert_nil a.col_dim
    assert_equal "amount", a.metric
  end
end
