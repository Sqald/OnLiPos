require "test_helper"

# 端末側からの不正・データ不整合を防ぐ検証（承認・価格・返金・レシート連番）
class SaleIntegrityApiTest < ActionDispatch::IntegrationTest
  setup do
    AutoOperatorApproval.enabled = false
    @user = User.create!(login_name: "integrity", email: "integrity@example.com", password: "Password1!", password_confirmation: "Password1!",
                         first_name: "a", last_name: "b", user_type: :individual, confirmed_at: Time.current)
    @store = @user.stores.create!(name: "S1", ascii_name: "storeone")
    @other_store = @user.stores.create!(name: "S2", ascii_name: "storetwo")
    @pos = @store.pos_tokens.create!(name: "P1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos.regenerate_token
    @manager1 = employee("E1", "1234", "refund", "discount", "open_register", "close_register", "cash_check")
    @manager2 = employee("E2", "5678", "refund")
    @staff = employee("E3", "1111")
    @product = @user.products.create!(code: "A", name: "A", price: 10_000, tax_rate: 10)
  end

  teardown { AutoOperatorApproval.enabled = true }

  def employee(code, pin, *permissions)
    @user.employees.create!(code: code, name: code, pin: pin).tap do |e|
      e.stores << @store
      permissions.each { |p| e.employee_permissions.create!(permission: p) }
    end
  end

  def auth(*approvals)
    headers = { "Authorization" => "Bearer #{@pos.token}" }
    headers["X-Operator-Approval"] = approvals.join(",") if approvals.any?
    headers
  end

  # PIN認証して承認トークンを得る
  def approve(employee, pin, permission)
    post "/api/v1/pos_devices/verify_employee", params: { code: employee.code, pin: pin, permission: permission }, headers: auth, as: :json
    assert_response :ok
    response.parsed_body["approval_token"]
  end

  def refund_approvals = [ approve(@manager1, "1234", "refund"), approve(@manager2, "5678", "refund") ]

  def line(**overrides)
    { product_id: @product.id, product_name: "A", quantity: 1, unit_price: 10_000, subtotal: 10_000, tax_rate: 10 }.merge(overrides)
  end

  def post_sale(details, total, by: @staff, approvals: [], **sale)
    post "/api/v1/sales", params: {
      employee_id: by.id, sale: { total_amount: total, payment_method: 0 }.merge(sale), details: details,
      payments: [ { method: 0, amount: total } ]
    }, headers: auth(*approvals), as: :json
    Sale.find_by(id: response.parsed_body["sale_id"])
  end

  def post_refund(sale, approvals: [], quantity: 1, payments: nil)
    post "/api/v1/refunds", params: {
      receipt_number: sale.receipt_number, employee_ids: [ @manager1.id, @manager2.id ],
      details: [ { saledetail_id: sale.saledetails.first.id, quantity: quantity } ], payments: payments
    }.compact, headers: auth(*approvals), as: :json
  end

  def open_register
    post "/api/v1/pos_devices/open", params: {
      employee_id: @manager1.id, open_date: Date.current.to_s,
      cash_drawer: { "10000" => 1, "5000" => 0, "1000" => 0, "500" => 0, "100" => 0, "50" => 0, "10" => 0, "5" => 0, "1" => 0 }
    }, headers: auth(approve(@manager1, "1234", "open_register")), as: :json
    assert_response :ok
  end

  def offline_number(sequence) = "integrity-storeone-#{@pos.id}-#{sequence.to_s.rjust(8, '0')}"

  # ── 承認 ──
  test "従業員IDを送るだけでは返品できず、2名のPIN認証があればできる" do
    sale = post_sale([ line ], 10_000)
    post_refund(sale)
    assert_response :forbidden
    assert_equal "operator_approval_required", response.parsed_body["code"]

    post_refund(sale, approvals: [ approve(@manager1, "1234", "refund") ])
    assert_response :forbidden

    post_refund(sale, approvals: refund_approvals)
    assert_response :created
  end

  test "返品の承認は1回しか使えない" do
    approvals = refund_approvals
    sales = Array.new(2) { post_sale([ line ], 10_000) }
    post_refund(sales[0], approvals: approvals)
    assert_response :created
    post_refund(sales[1], approvals: approvals)
    assert_response :forbidden
  end

  test "別の権限・別の端末・期限切れの承認は使えない" do
    sale = post_sale([ line ], 10_000)
    valid = approve(@manager2, "5678", "refund")

    post_refund(sale, approvals: [ approve(@manager1, "1234", "discount"), valid ])
    assert_response :forbidden

    other = @store.pos_tokens.create!(name: "P2", ascii_name: "pos2", password: "PosPass1!", password_confirmation: "PosPass1!")
    _, foreign = OperatorApproval.issue!(employee: @manager1, pos_token: other, permission: "refund")
    post_refund(sale, approvals: [ foreign, valid ])
    assert_response :forbidden

    record, expired = OperatorApproval.issue!(employee: @manager1, pos_token: @pos, permission: "refund")
    record.update_columns(expires_at: 1.second.ago)
    post_refund(sale, approvals: [ expired, valid ])
    assert_response :forbidden
  end

  test "権限を失った担当者の承認は使えない" do
    approvals = refund_approvals
    sale = post_sale([ line ], 10_000)
    @manager2.sync_permissions([])
    post_refund(sale, approvals: approvals)
    assert_response :forbidden
  end

  test "理論在高は承認なしでは参照できない" do
    get "/api/v1/pos_devices/cash_check_context", headers: auth
    assert_response :forbidden
    get "/api/v1/pos_devices/cash_check_context", headers: auth(approve(@manager1, "1234", "cash_check"))
    assert_response :ok
  end

  test "所属していない店舗では販売できない" do
    outsider = @user.employees.create!(code: "E9", name: "外", pin: "9999")
    outsider.stores << @other_store
    post_sale([ line ], 10_000, by: outsider)
    assert_response :unprocessable_entity
  end

  # ── 価格・税率 ──
  test "権限者の認証なしに通常と異なる単価では販売できず、認証があれば割引額はサーバーで計算される" do
    post_sale([ line(unit_price: 1, subtotal: 1, original_unit_price: 10_000) ], 1)
    assert_response :forbidden
    assert_equal "discount_approval_required", response.parsed_body["code"]

    sale = post_sale([ line(unit_price: 9000, subtotal: 9000, original_unit_price: 1) ], 9000, approvals: [ approve(@manager1, "1234", "discount") ])
    assert_response :created
    assert_equal @manager1, sale.discount_approver
    assert_equal 1000, sale.total_discount
    assert_equal 10_000, sale.saledetails.first.original_unit_price
  end

  test "小計が単価×数量と一致しない・負の小計は拒否する" do
    post_sale([ line(unit_price: 10_000, subtotal: 1) ], 1)
    assert_response :unprocessable_entity
    post_sale([ line, line(unit_price: 0, subtotal: -9999) ], 1)
    assert_response :unprocessable_entity
    assert_equal 0, Sale.count
  end

  test "税率がマスタと異なるとマスタ同期を促して拒否する" do
    post_sale([ line(tax_rate: 0) ], 10_000)
    assert_response :conflict
    assert_equal "master_outdated", response.parsed_body["code"]
  end

  test "価格変更の直後は、変更前の価格でも販売できる（端末の同期待ち）" do
    @product.update!(price: 12_000)
    post_sale([ line ], 10_000)
    assert_response :created
    ProductPriceHistory.update_all(replaced_at: 2.days.ago)
    post_sale([ line ], 10_000)
    assert_response :forbidden
  end

  test "店舗価格・定価のどちらでも販売でき、店舗価格の変更は差分同期に含まれる" do
    before = 1.second.from_now
    travel 2.seconds
    Price.create!(store: @store, product: @product, amount: 8000)
    post_sale([ line(unit_price: 8000, subtotal: 8000) ], 8000)
    assert_response :created
    post_sale([ line ], 10_000)
    assert_response :created

    post "/api/v1/products/sync", params: { last_updated_at: before.iso8601(6), last_id: 0 }, headers: auth, as: :json
    assert_equal [ @product.id ], response.parsed_body["products"].map { |p| p["id"] }
  end

  test "オフライン会計は価格が異なっても登録し、要確認にする" do
    sale = post_sale([ line(unit_price: 1, subtotal: 1) ], 1, receipt_number: offline_number(1), sold_at: 1.hour.ago.iso8601)
    assert_response :created
    assert sale.offline?
    assert_match "通常と異なる価格", sale.review_reasons.first
    assert_includes Sale.needing_review, sale
  end

  # ── オフライン会計 ──
  test "オフライン会計を同期した後もオンライン会計を登録できる" do
    post_sale([ line ], 10_000, receipt_number: offline_number(1))
    assert_response :created
    assert_equal 2, response.parsed_body["next_receipt_sequence"]

    sale = post_sale([ line ], 10_000)
    assert_response :created
    assert_equal offline_number(2), sale.receipt_number
  end

  test "過去に連番が反映されていない端末も、使用済みの番号を飛ばして復旧する" do
    post_sale([ line ], 10_000, receipt_number: offline_number(1))
    @pos.update_columns(next_receipt_sequence: 1)
    sale = post_sale([ line ], 10_000)
    assert_equal offline_number(2), sale.receipt_number
  end

  test "形式外・極端に先の番号は採用しない" do
    [ "=HYPERLINK(\"http://x\")-#{@pos.id}-00000009", offline_number(99_999_999) ].each do |number|
      sale = post_sale([ line ], 10_000, receipt_number: number)
      assert_response :created
      assert_not_equal number, sale.receipt_number
    end
  end

  test "オフライン会計は販売時の営業日・レジセッションに計上し、オンライン会計は端末時刻を使わない" do
    session = @pos.register_sessions.create!(user: @user, store: @store, business_date: Date.new(2026, 10, 1), z_number: 1, status: :closed,
                                             opened_at: Time.zone.local(2026, 10, 1, 9), closed_at: Time.zone.local(2026, 10, 1, 21), closing_counted_amount: 0)
    open_register
    sale = post_sale([ line ], 10_000, receipt_number: offline_number(5), sold_at: "2026-10-01T10:00:00+09:00")
    assert_equal Date.new(2026, 10, 1), sale.business_date
    assert_equal session, sale.register_session
    assert_match "精算の後", sale.review_reasons.first

    sale = post_sale([ line ], 10_000, sold_at: "2031-01-01T00:00:00+09:00")
    assert_in_delta Time.current, sale.sold_at, 60
  end

  # ── 返品・取消 ──
  test "取消済みの会計は返品できない" do
    open_register
    sale = post_sale([ line ], 10_000)
    post "/api/v1/sales/#{sale.id}/void", params: { employee_ids: [ @manager1.id, @manager2.id ], reason: "誤登録" }, headers: auth(*refund_approvals), as: :json
    assert_response :ok
    post_refund(sale, approvals: refund_approvals)
    assert_response :unprocessable_entity
    assert_equal 10_000, RegisterSession.last.expected_cash_now
  end

  test "量り売りは支払額が返金される" do
    weighed = @user.products.create!(code: "W", name: "W", price: 200, tax_rate: 8, sold_by_weight: true)
    sale = post_sale([ { product_id: weighed.id, quantity: 1, unit_price: 200, subtotal: 1000, tax_rate: 8, weight_grams: 500 } ], 1000)
    post_refund(sale, approvals: refund_approvals)
    assert_equal 1000, response.parsed_body["total_refund_amount"]
  end

  test "分割して返品しても合計が支払額と一致し、それを超えない" do
    sale = post_sale([ line(quantity: 3, subtotal: 30_000) ], 29_999, approvals: [ approve(@manager1, "1234", "discount") ],
                     order_discount_type: "amount", order_discount_value: 1)
    assert_response :created
    amounts = Array.new(3) { post_refund(sale, approvals: refund_approvals); response.parsed_body["total_refund_amount"] }
    assert_equal 29_999, amounts.sum
    post_refund(sale, approvals: refund_approvals)
    assert_response :unprocessable_entity
  end

  test "過去データの単価が大きくても、会計の支払額を超えて返金しない" do
    sale = post_sale([ line ], 10_000)
    sale.saledetails.first.update_columns(unit_price: 100_000)
    post_refund(sale, approvals: refund_approvals)
    assert_equal 10_000, response.parsed_body["total_refund_amount"]
  end

  test "返金の決済手段は元の支払いに応じて記録され、カード返金は支払額を超えられない" do
    sale = post_sale([ line ], 10_000)
    sale.sale_payments.delete_all
    sale.sale_payments.create!(method: :cash, amount: 4000)
    sale.sale_payments.create!(method: :card, amount: 6000)
    post_refund(sale, approvals: refund_approvals, payments: [ { method: 1, amount: 10_000 } ])
    assert_response :unprocessable_entity
    post_refund(sale, approvals: refund_approvals)
    assert_response :created
    assert_equal({ "cash" => 4000, "card" => 6000 }, RefundPayment.group(:method).sum(:amount))
  end
end
