# 返品側に税情報と営業日・セッションの紐付けを追加し、売上と対称に相殺できるようにする。
# refund_details に販売時点の税率・税額を保存することで、
# 税率別集計から返品分を正確に控除できる（現状は返金総額のみで税の内訳が失われる）。
class AddAccountingFieldsToRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :refunds, :subtotal_ex_tax, :integer, null: false, default: 0
    add_column :refunds, :tax_amount, :integer, null: false, default: 0
    add_reference :refunds, :register_session, foreign_key: true
    add_column :refunds, :refunded_at, :datetime
    add_column :refunds, :business_date, :date

    add_column :refund_details, :tax_rate, :integer, null: false, default: 0
    add_column :refund_details, :tax_amount, :integer, null: false, default: 0

    add_index :refunds, [ :store_id, :business_date ]

    # 既存行の営業日を補完（追記のみ）
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE refunds
          SET refunded_at = created_at,
              business_date = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Tokyo')::date
          WHERE refunded_at IS NULL
        SQL
      end
    end
  end
end
