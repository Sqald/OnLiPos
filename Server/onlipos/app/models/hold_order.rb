# 保留中の会計（オーダーストップ等で一時保存された取引）
class HoldOrder < ApplicationRecord
  belongs_to :store

  # バリデーション
  validates :operator_name, presence: true
  validates :operator_id, presence: true
  validates :total_amount, presence: true
end
