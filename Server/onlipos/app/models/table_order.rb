# 飲食店等のテーブル管理（卓番号ごとの注文状態を管理する）
class TableOrder < ApplicationRecord
  belongs_to :store

  validates :table_number, presence: true
  validates :table_number, uniqueness: { scope: :store_id }
end
