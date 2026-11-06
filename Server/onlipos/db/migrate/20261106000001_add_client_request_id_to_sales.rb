# 会計送信の冪等キー。POS端末が会計ごとに採番し、タイムアウト後の再送（オフラインキュー）でも
# 同じ値を送ることで、サーバー側で同一会計の二重登録を検出できるようにする。
class AddClientRequestIdToSales < ActiveRecord::Migration[8.1]
  def change
    add_column :sales, :client_request_id, :string
    add_index :sales, %i[pos_token_id client_request_id], unique: true,
              where: "client_request_id IS NOT NULL",
              name: "index_sales_on_pos_token_id_and_client_request_id"
  end
end
