class CreateEmployeesStores < ActiveRecord::Migration[7.1]
  def change
    create_join_table :employees, :stores do |t|
      t.index [:employee_id, :store_id]
      t.index [:store_id, :employee_id]
    end
  end
end
