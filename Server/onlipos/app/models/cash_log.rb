class CashLog < ApplicationRecord
  belongs_to :pos_token
  belongs_to :employee

  validates :open_date, presence: true
  
  # 金種カラムのバリデーション (0以上であること)
  validates :yen_10000, :yen_5000, :yen_1000, :yen_500, :yen_100, :yen_50, :yen_10, :yen_5, :yen_1, 
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # 合計金額を計算するメソッド
  def total_amount
    (yen_10000 * 10000) + (yen_5000 * 5000) + (yen_1000 * 1000) + 
    (yen_500 * 500) + (yen_100 * 100) + (yen_50 * 50) + 
    (yen_10 * 10) + (yen_5 * 5) + (yen_1 * 1)
  end
end