# レジセッション（開設〜精算の1営業単位）。
# Zレポートの区切り・現金照合の基準期間として使う。
# 精算時に集計値スナップショットを確定保存し、以後の集計はセッション単位で貸借が合うようにする。
class CreateRegisterSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :register_sessions do |t|
      t.references :user,      null: false, foreign_key: true
      t.references :store,     null: false, foreign_key: true
      t.references :pos_token, null: false, foreign_key: true

      t.date    :business_date, null: false
      t.bigint  :z_number,      null: false                 # 端末ごとの精算連番（Zカウンタ）
      t.integer :status,        null: false, default: 0     # 0: open, 1: closed

      t.datetime :opened_at, null: false
      t.datetime :closed_at
      t.references :opening_employee, foreign_key: { to_table: :employees }
      t.references :closing_employee, foreign_key: { to_table: :employees }

      # 現金照合（精算時に確定）
      t.integer :opening_float, null: false, default: 0     # 釣銭準備金（開設時実査額）
      t.integer :closing_counted_amount                     # 精算時実査額
      t.integer :expected_cash_amount                       # 理論在高
      t.integer :cash_diff_amount                           # 過不足（実査 - 理論）
      t.integer :next_opening_float                         # 翌営業日釣銭準備金

      # 精算時集計スナップショット（closed 後は変更しない）
      t.integer :sales_count
      t.integer :sales_total
      t.integer :refund_count
      t.integer :refund_total
      t.integer :void_count
      t.integer :void_total
      t.integer :discount_total
      t.integer :cash_sales_total
      t.integer :cash_refund_total
      t.integer :cash_in_total
      t.integer :cash_out_total
      t.jsonb   :closing_summary, null: false, default: {}  # Zレポート印字用の詳細（税率別・決済手段別内訳等）

      t.timestamps
    end

    add_index :register_sessions, [ :pos_token_id, :z_number ], unique: true
    add_index :register_sessions, [ :store_id, :business_date ]
    # 1端末につき open なセッションは同時に1つまで
    add_index :register_sessions, :pos_token_id,
              unique: true, where: "status = 0", name: "index_register_sessions_open_per_pos"

    add_check_constraint :register_sessions, "opening_float >= 0", name: "register_sessions_opening_float_non_negative"
  end
end
