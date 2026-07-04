require "test_helper"

# 電子ジャーナルの追記型化（連番採番・ハッシュチェーン・readonly）のテスト。
class JournalEntryChainTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      login_name: "jchain#{SecureRandom.hex(3)}",
      email: "jchain#{SecureRandom.hex(3)}@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "テスト",
      user_type: :individual,
      confirmed_at: Time.current
    )
    @store = @user.stores.create!(name: "ジャーナル店舗#{SecureRandom.hex(3)}", ascii_name: "jchain#{SecureRandom.hex(2)}")
    @pos_token = @store.pos_tokens.create!(name: "POS1", ascii_name: "pos1", password: "PosPass1!", password_confirmation: "PosPass1!")
    @employee = @user.employees.create!(code: "E001", name: "田中一郎")
    @employee.stores << @store
  end

  def create_entry(payload = { total_amount: 1000 })
    JournalEntry.create!(
      user: @user, store: @store, pos_token: @pos_token, employee: @employee,
      entry_type: :sale, printed_at: Time.current, payload: payload
    )
  end

  test "作成時に連番とハッシュチェーンが自動採番される" do
    first = create_entry
    second = create_entry

    assert_equal 1, first.sequence_number
    assert_equal 2, second.sequence_number
    assert_equal JournalEntry::GENESIS_HASH, first.previous_hash
    assert_equal first.entry_hash, second.previous_hash
    assert_equal 3, @pos_token.reload.next_journal_sequence
  end

  test "保存されたハッシュはDBから読み戻して再計算した値と一致する" do
    entry = create_entry({ total_amount: 999, details: [ { product_name: "商品A", quantity: 2 } ] })

    reloaded = JournalEntry.find(entry.id)
    assert_equal reloaded.entry_hash, reloaded.compute_entry_hash
  end

  test "健全なチェーンは verify_chain で問題なし" do
    3.times { create_entry }
    assert_empty JournalEntry.verify_chain(@pos_token)
  end

  test "payload を改ざんすると verify_chain が検知する" do
    create_entry
    target = create_entry({ total_amount: 5000 })
    create_entry

    # readonly を迂回するDB直接更新（改ざんのシミュレーション）
    JournalEntry.where(id: target.id).update_all("payload = '{\"total_amount\":1}'::jsonb")

    issues = JournalEntry.verify_chain(@pos_token)
    assert issues.any? { |i| i.include?("改ざん検知") }, "改ざんが検知されること: #{issues}"
  end

  test "エントリを削除すると verify_chain が欠番とチェーン切断を検知する" do
    create_entry
    middle = create_entry
    create_entry

    # readonly を迂回するDB直接削除（抜き取りのシミュレーション）
    JournalEntry.where(id: middle.id).delete_all

    issues = JournalEntry.verify_chain(@pos_token)
    assert issues.any? { |i| i.include?("連番不整合") || i.include?("チェーン切断") }, "欠番が検知されること: #{issues}"
  end

  test "作成後の更新・削除は readonly で拒否される" do
    entry = create_entry

    assert_raises(ActiveRecord::ReadOnlyRecord) { entry.update!(receipt_number: "X") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { JournalEntry.find(entry.id).destroy }
  end

  test "既存のレガシー行（連番なし）が混在しても新規エントリからチェーンを開始できる" do
    legacy = JournalEntry.new(
      user: @user, store: @store, pos_token: @pos_token,
      entry_type: :sale, printed_at: Time.current, payload: { total_amount: 1 }
    )
    legacy.save!(validate: false)
    JournalEntry.where(id: legacy.id).update_all(sequence_number: nil, previous_hash: nil, entry_hash: nil)

    entry = create_entry
    assert_equal 2, entry.sequence_number # 採番カウンタはレガシー行の分も消費済み
    assert_equal JournalEntry::GENESIS_HASH, entry.previous_hash
    assert_empty JournalEntry.verify_chain(@pos_token)
  end
end
