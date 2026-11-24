# 掛売残高の増減履歴（会計で増え、入金・返品で減る）
class ReceivableTransaction < ApplicationRecord
  belongs_to :customer
  belongs_to :sale, optional: true
  belongs_to :refund, optional: true
end
