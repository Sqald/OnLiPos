# 決済手段。Sale / SalePayment / RefundPayment とクライアントで番号を共有する。
module PaymentMethods
  VALUES = { cash: 0, card: 1, barcode: 2, emoney: 3, points: 4, voucher: 5, house_account: 6 }.freeze
  LABELS = {
    "cash" => "現金", "card" => "カード", "barcode" => "バーコード決済", "emoney" => "電子マネー",
    "points" => "ポイント", "voucher" => "商品券", "house_account" => "掛売"
  }.freeze
  # 数値コード（文字列）=> 表示名
  LABELS_BY_CODE = VALUES.to_h { |name, code| [ code.to_s, LABELS[name.to_s] ] }.freeze
  # 会員の指定が必要な決済手段
  CUSTOMER_REQUIRED = %w[points house_account].freeze

  def self.label(name) = LABELS.fetch(name.to_s, name.to_s)
end
