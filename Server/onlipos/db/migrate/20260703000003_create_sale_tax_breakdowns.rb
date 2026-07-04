# 売上ごとの税率別内訳（適格簡易請求書の記載事項の保持先）。
# 「1レシートにつき税率ごとに端数処理1回」を満たすため、
# 明細の積み上げではなく確定値としてここに保存する。
class CreateSaleTaxBreakdowns < ActiveRecord::Migration[8.1]
  def change
    create_table :sale_tax_breakdowns do |t|
      t.references :sale, null: false, foreign_key: true
      t.integer :tax_rate, null: false                    # 8, 10 など（%）
      t.integer :tax_type, null: false, default: 0        # 0: 内税, 1: 外税, 2: 非課税
      t.integer :taxable_amount, null: false, default: 0  # 税率ごとに区分した税込対価の合計
      t.integer :amount_ex_tax,  null: false, default: 0  # 税抜額
      t.integer :tax_amount,     null: false, default: 0  # 消費税額（税率ごとに端数処理1回）

      t.timestamps
    end

    add_index :sale_tax_breakdowns, [ :sale_id, :tax_rate, :tax_type ],
              unique: true, name: "index_sale_tax_breakdowns_uniqueness"

    add_check_constraint :sale_tax_breakdowns,
                         "taxable_amount >= 0 AND amount_ex_tax >= 0 AND tax_amount >= 0",
                         name: "sale_tax_breakdowns_amounts_non_negative"
  end
end
