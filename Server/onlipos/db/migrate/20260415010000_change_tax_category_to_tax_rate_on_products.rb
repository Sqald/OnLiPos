class ChangeTaxCategoryToTaxRateOnProducts < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :tax_rate, :integer, default: 10, null: false

    # 既存データの移行: standard(0) → 10%, reduced(1) → 8%
    execute <<~SQL
      UPDATE products SET tax_rate = CASE tax_category WHEN 1 THEN 8 ELSE 10 END
    SQL

    remove_column :products, :tax_category
  end

  def down
    add_column :products, :tax_category, :integer, default: 0, null: false

    execute <<~SQL
      UPDATE products SET tax_category = CASE WHEN tax_rate = 8 THEN 1 ELSE 0 END
    SQL

    remove_column :products, :tax_rate
  end
end
