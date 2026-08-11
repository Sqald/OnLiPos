# 客層キー（東芝テック製レジ等の業務用POSに見られる、性別・年代による客層データ収集機能）。
# レジ担当者が会計時に任意で選択する匿名の属性であり、顧客個人を特定する会員管理とは別物。
class AddCustomerSegmentToSales < ActiveRecord::Migration[8.1]
  def change
    add_column :sales, :customer_gender, :integer     # 0: 男性, 1: 女性, 2: その他（NULL = 未選択）
    add_column :sales, :customer_age_group, :integer   # 0: ~19, 1: 20s, 2: 30s, 3: 40s, 4: 50s, 5: 60~（NULL = 未選択）
  end
end
