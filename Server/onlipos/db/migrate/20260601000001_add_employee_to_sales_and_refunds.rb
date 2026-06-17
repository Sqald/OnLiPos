class AddEmployeeToSalesAndRefunds < ActiveRecord::Migration[8.1]
  def change
    add_reference :sales,   :employee, null: true, foreign_key: true
    add_reference :refunds, :employee, null: true, foreign_key: true
  end
end
