# オプションの選択肢（追加料金は0円以上）
class OptionItem < ApplicationRecord
  belongs_to :option_group

  validates :name, presence: true
  validates :price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
