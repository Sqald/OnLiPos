# ポイントの増減履歴
class PointTransaction < ApplicationRecord
  belongs_to :customer
  belongs_to :sale, optional: true
  belongs_to :refund, optional: true

  enum :kind, { earned: 0, used: 1, reversed: 2, returned: 3, adjusted: 4 }
  KIND_LABELS = { "earned" => "付与", "used" => "利用", "reversed" => "付与の取消", "returned" => "利用分の返却", "adjusted" => "手動調整" }.freeze
end
