# 返金の決済手段別内訳。過去の返品は従来の按分式（元売上の現金比率）で確定して移行する。
class CreateRefundPayments < ActiveRecord::Migration[8.1]
  def up
    create_table :refund_payments do |t|
      t.references :refund, null: false, foreign_key: true
      t.integer :method, null: false
      t.integer :amount, null: false
      t.string :label
      t.string :external_reference
      t.timestamps
      t.check_constraint "amount > 0", name: "refund_payments_amount_positive"
    end

    execute <<~SQL
      WITH base AS (
        SELECT r.id, r.total_amount, s.payment_method,
               LEAST(r.total_amount, ROUND(r.total_amount::numeric * COALESCE(c.cash, 0) / NULLIF(s.total_amount, 0)))::int AS cash,
               (SELECT p.method FROM sale_payments p WHERE p.sale_id = s.id AND p.method <> 0 ORDER BY p.amount DESC LIMIT 1) AS other_method
        FROM refunds r
        JOIN sales s ON s.id = r.sale_id
        LEFT JOIN (SELECT sale_id, SUM(amount) AS cash FROM sale_payments WHERE method = 0 GROUP BY sale_id) c ON c.sale_id = s.id
        WHERE r.total_amount > 0 AND s.total_amount > 0
      )
      INSERT INTO refund_payments (refund_id, method, amount, created_at, updated_at)
      SELECT id, 0, cash, NOW(), NOW() FROM base WHERE cash > 0
      UNION ALL
      SELECT id, COALESCE(other_method, payment_method), total_amount - cash, NOW(), NOW() FROM base WHERE total_amount - cash > 0
    SQL
  end

  def down
    drop_table :refund_payments
  end
end
