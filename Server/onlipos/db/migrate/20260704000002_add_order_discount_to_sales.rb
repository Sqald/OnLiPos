# 小計割引（会計全体への金額/％割引）。
# 割引は登録時に明細へ按分され税再計算されるため、ここには
# 「どんな割引指示だったか」の監査情報と確定割引額を保持する。
class AddOrderDiscountToSales < ActiveRecord::Migration[8.1]
  def change
    add_column :sales, :order_discount_type, :integer          # 0: 金額, 1: パーセント（NULL = 割引なし）
    add_column :sales, :order_discount_value, :integer          # 指定値（円 or %）
    add_column :sales, :order_discount_total, :integer, null: false, default: 0 # 確定割引額（円）
    add_column :sales, :order_discount_reason, :string
  end
end
