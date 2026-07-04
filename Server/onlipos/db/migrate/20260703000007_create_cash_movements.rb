# レジ現金の入出金（釣銭補充・両替・雑入出金・途中回収）を金額±で一元記録する。
# 現状 cash_logs に金種ゼロ埋めで混在している途中回収（is_pickup）の後継。
# 理論在高 = 釣銭準備金 + 現金売上 - 現金返金 + 入金合計 - 出金合計 がこのテーブルだけで閉じる。
class CreateCashMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :cash_movements do |t|
      t.references :store,            null: false, foreign_key: true
      t.references :pos_token,        null: false, foreign_key: true
      t.references :register_session, foreign_key: true
      t.references :employee,         null: false, foreign_key: true

      t.integer :kind, null: false       # 0: pickup(途中回収), 1: replenishment(釣銭補充), 2: misc_in(雑入金), 3: misc_out(雑出金)
      t.integer :direction, null: false  # 0: in(入金), 1: out(出金)
      t.integer :amount, null: false     # 常に正の金額。方向は direction で表す
      t.string  :reason
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :cash_movements, [ :pos_token_id, :occurred_at ]
    add_index :cash_movements, [ :store_id, :occurred_at ]

    add_check_constraint :cash_movements, "amount > 0", name: "cash_movements_amount_positive"
  end
end
