# 売上の税率別内訳（適格簡易請求書の記載事項の確定保存先）。
# 「1レシートにつき税率ごとに端数処理1回」を満たすため、
# 登録時に確定した値を保存し、集計・レシート印字はこの値をそのまま使う。
class SaleTaxBreakdown < ApplicationRecord
  belongs_to :sale

  # 0: 内税, 1: 外税, 2: 非課税
  enum :tax_type, { inclusive: 0, exclusive: 1, tax_free: 2 }

  validates :tax_rate, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 },
                       uniqueness: { scope: [ :sale_id, :tax_type ] }
  validates :taxable_amount, :amount_ex_tax, :tax_amount,
            presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
