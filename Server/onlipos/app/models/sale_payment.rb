class SalePayment < ApplicationRecord
  belongs_to :sale

  # 支払い方法: 0:現金, 1:カード, 2:バーコード決済
  # Saleモデルのenumと番号を揃えることで、クライアントとの互換性を保ちます。
  enum :method, { cash: 0, card: 1, barcode: 2 }

  validates :amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
end

