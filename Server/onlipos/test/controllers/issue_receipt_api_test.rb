require "test_helper"

# 領収書発行 API のテスト。
# 発行履歴のジャーナル記録・再発行判定・インボイス記載事項の返却を確認する。
class IssueReceiptApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      login_name: "receipttest",
      email: "receipttest@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current,
      invoice_registration_number: "T1234567890123"
    )
    @store = @user.stores.create!(name: "領収書テスト店舗", ascii_name: "rcptstore")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @pos_token.update_columns(token: SecureRandom.hex(32))
    @auth = { "Authorization" => "Bearer #{@pos_token.token}" }

    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store

    @product = @user.products.create!(code: "P001", name: "商品A", price: 55_000, tax_rate: 10)
    StoreStock.create!(store: @store, product: @product, quantity: 10)

    post "/api/v1/sales",
         params: {
           sale: { total_amount: 55_000, subtotal_ex_tax: 0, tax_amount: 0 },
           employee_id: @employee.id,
           details: [ { product_id: @product.id, quantity: 1, unit_price: 55_000, subtotal: 55_000, tax_rate: 10 } ],
           payments: [ { method: 0, amount: 55_000 } ]
         },
         headers: @auth, as: :json
    @sale = Sale.find(JSON.parse(response.body)["sale_id"])
  end

  def issue(addressee: "株式会社テスト商事", purpose: "お品代として")
    post "/api/v1/sales/#{@sale.id}/issue_receipt",
         params: { employee_id: @employee.id, addressee: addressee, purpose: purpose },
         headers: @auth, as: :json
  end

  test "領収書発行がジャーナルに記録されインボイス記載事項が返る" do
    assert_difference -> { JournalEntry.receipt_issue.count }, 1 do
      issue
    end
    assert_response :created
    data = JSON.parse(response.body)

    assert_equal false, data["reissue"]
    receipt = data["receipt"]
    assert_equal "株式会社テスト商事", receipt["addressee"]
    assert_equal "お品代として", receipt["purpose"]
    assert_equal 55_000, receipt["total_amount"]
    assert_equal "T1234567890123", receipt["invoice_registration_number"]
    assert_equal true, receipt["revenue_stamp_required"] # 5万円以上
    assert_equal 10, receipt["tax_breakdowns"].first["tax_rate"]

    entry = JournalEntry.receipt_issue.last
    assert_equal "株式会社テスト商事", entry.payload["addressee"]
    assert_equal false, entry.payload["reissue"]
    assert_equal @sale.receipt_number, entry.receipt_number
  end

  test "2回目の発行は再発行として記録される" do
    issue
    assert_response :created

    issue
    assert_response :created
    data = JSON.parse(response.body)
    assert_equal true, data["reissue"]
    assert_equal true, JournalEntry.receipt_issue.last.payload["reissue"]
  end

  test "取消済みの会計には発行できない" do
    @sale.update!(status: :voided, voided_at: Time.current, void_reason: "誤登録")

    issue
    assert_response :unprocessable_entity
  end

  test "他店舗の売上には発行できない" do
    other_store = @user.stores.create!(name: "他店舗", ascii_name: "otherrcpt")
    other_pos = other_store.pos_tokens.create!(name: "POS2", ascii_name: "pos2", password: "PosPass1!", password_confirmation: "PosPass1!")
    other_pos.update_columns(token: SecureRandom.hex(32))

    post "/api/v1/sales/#{@sale.id}/issue_receipt",
         params: { addressee: "X" },
         headers: { "Authorization" => "Bearer #{other_pos.token}" }, as: :json
    assert_response :not_found
  end
end
