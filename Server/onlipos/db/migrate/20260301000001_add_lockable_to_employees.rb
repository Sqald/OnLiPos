class AddLockableToEmployees < ActiveRecord::Migration[8.1]
  def change
    add_column :employees, :failed_attempts, :integer, default: 0, null: false
    add_column :employees, :locked_at, :datetime
  end
end
