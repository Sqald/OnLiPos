# Sale の支払い内訳（1回の会計を複数の支払い方法に分けた場合、複数行になる）
class SalePayment < ApplicationRecord
  belongs_to :sale

  # 支払い方法: 0:現金, 1:カード, 2:バーコード決済, 3:電子マネー
  # Saleモデルのenumと番号を揃えることで、クライアントとの互換性を保ちます。
  enum :method, { cash: 0, card: 1, barcode: 2, emoney: 3 }

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
end
