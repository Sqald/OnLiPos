# 返品ごとの税率別内訳（売上と対称の構造）。
# 返還インボイス（適格返還請求書）の記載事項と、税率別売上集計からの正確な控除に使う。
class CreateRefundTaxBreakdowns < ActiveRecord::Migration[8.1]
  def change
    create_table :refund_tax_breakdowns do |t|
      t.references :refund, null: false, foreign_key: true
      t.integer :tax_rate, null: false
      t.integer :tax_type, null: false, default: 0        # 0: 内税, 1: 外税, 2: 非課税
      t.integer :taxable_amount, null: false, default: 0
      t.integer :amount_ex_tax,  null: false, default: 0
      t.integer :tax_amount,     null: false, default: 0

      t.timestamps
    end

    add_index :refund_tax_breakdowns, [ :refund_id, :tax_rate, :tax_type ],
              unique: true, name: "index_refund_tax_breakdowns_uniqueness"

    add_check_constraint :refund_tax_breakdowns,
                         "taxable_amount >= 0 AND amount_ex_tax >= 0 AND tax_amount >= 0",
                         name: "refund_tax_breakdowns_amounts_non_negative"
  end
end
