# 会計の要確認フラグ（オフライン会計の価格相違・精算後の後着など）と、値引きの承認者・後送元の記録
class AddReviewColumnsToSales < ActiveRecord::Migration[8.1]
  def change
    add_column :sales, :review_reasons, :jsonb, null: false, default: []
    add_column :sales, :reviewed_at, :datetime
    add_column :sales, :reviewed_by_name, :string
    add_column :sales, :offline, :boolean, null: false, default: false
    add_reference :sales, :discount_approver, foreign_key: { to_table: :employees }
    add_index :sales, [ :user_id, :reviewed_at ], where: "review_reasons <> '[]'::jsonb", name: "index_sales_needing_review"
  end
end
