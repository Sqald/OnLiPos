class CreateEmployeePermissions < ActiveRecord::Migration[8.1]
  INITIAL_PERMISSIONS = %w[
    open_register close_register cash_check cash_pickup
    refund view_sales edit_prices view_journal inventory discount
  ].freeze

  def up
    create_table :employee_permissions do |t|
      t.references :employee, null: false, foreign_key: true
      t.string :permission, null: false
      t.timestamps
    end

    add_index :employee_permissions, %i[employee_id permission], unique: true

    # 既存従業員に全権限を付与（マイグレーション後も従来通り操作できるようにする）
    now = Time.current.utc.strftime('%Y-%m-%d %H:%M:%S')
    Employee.ids.each do |eid|
      INITIAL_PERMISSIONS.each do |key|
        execute(<<~SQL.squish)
          INSERT INTO employee_permissions (employee_id, permission, created_at, updated_at)
          VALUES (#{eid}, '#{key}', '#{now}', '#{now}')
        SQL
      end
    end
  end

  def down
    drop_table :employee_permissions
  end
end
