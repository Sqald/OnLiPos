# 決済手段のサブ区分（電子マネーのブランド名等: Suica / iD / 楽天Edy など）。
# 決済手段別集計を実用的にするための任意項目。
class AddPaymentLabelToSalePayments < ActiveRecord::Migration[8.1]
  def change
    add_column :sale_payments, :label, :string
  end
end
