class AddTaxColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :products, :tax_category, :integer, default: 0, null: false

    add_column :saledetails, :tax_rate,   :integer, default: 0, null: false
    add_column :saledetails, :tax_amount, :integer, default: 0, null: false

    add_column :sales, :subtotal_ex_tax, :integer, default: 0, null: false
    add_column :sales, :tax_amount,      :integer, default: 0, null: false
  end
end
