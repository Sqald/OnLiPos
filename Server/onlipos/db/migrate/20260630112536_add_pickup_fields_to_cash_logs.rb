class AddPickupFieldsToCashLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :cash_logs, :is_pickup, :boolean, default: false, null: false
    add_column :cash_logs, :pickup_amount, :integer
    add_column :cash_logs, :pickup_reason, :string
  end
end
