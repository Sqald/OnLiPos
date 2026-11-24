# ダッシュボードの複数ユーザー（メンバー）と操作履歴
class CreateAuditLogsAndMembers < ActiveRecord::Migration[8.1]
  def change
    # owner_id があるユーザーは、その契約アカウントのメンバー。role で操作範囲を制限する
    add_reference :users, :owner, foreign_key: { to_table: :users }
    add_column :users, :role, :integer, null: false, default: 0

    create_table :audit_logs do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :actor_type
      t.bigint :actor_id
      t.string :actor_name
      t.string :action, null: false
      t.string :target_type
      t.bigint :target_id
      t.string :target_name
      t.jsonb :details, null: false, default: {}
      t.string :ip_address
      t.datetime :created_at, null: false
      t.index [ :user_id, :created_at ]
      t.index [ :target_type, :target_id ]
    end
  end
end
