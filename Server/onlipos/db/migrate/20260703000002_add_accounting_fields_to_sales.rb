# 売上ヘッダーに会計整合のためのフィールドを追加する。
# - status / void系: 確定後取消（VOID）を「削除」ではなく状態遷移として記録する
# - register_session: 精算（Z）単位の区切りに紐付ける
# - sold_at / business_date: オフライン後送でも売上計上日（営業日）がずれないようにする
class AddAccountingFieldsToSales < ActiveRecord::Migration[8.1]
  def change
    add_column :sales, :status, :integer, null: false, default: 0  # 0: completed, 1: voided
    add_column :sales, :voided_at, :datetime
    add_column :sales, :void_reason, :string
    add_reference :sales, :voided_by_employee, foreign_key: { to_table: :employees }

    add_reference :sales, :register_session, foreign_key: true

    add_column :sales, :sold_at, :datetime
    add_column :sales, :business_date, :date

    add_index :sales, [ :store_id, :business_date ]

    # 既存行は「サーバー受信時刻 = 売上時刻」として補完（追記のみ・既存カラムは変更しない）
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE sales
          SET sold_at = created_at,
              business_date = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Asia/Tokyo')::date
          WHERE sold_at IS NULL
        SQL
      end
    end
  end
end
