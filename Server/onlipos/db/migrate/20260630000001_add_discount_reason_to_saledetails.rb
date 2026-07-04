class AddDiscountReasonToSaledetails < ActiveRecord::Migration[8.1]
  def change
    add_column :saledetails, :discount_reason, :string, null: true
  end
end
