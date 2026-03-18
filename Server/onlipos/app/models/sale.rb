# /home/sqald/github/OnLiPos/Server/onlipos/app/models/sale.rb

class Sale < ApplicationRecord
  belongs_to :user
  belongs_to :store
  belongs_to :pos_token, optional: true
  has_many :saledetails, dependent: :destroy
  has_many :sale_payments, dependent: :destroy
  has_many :refunds, dependent: :restrict_with_exception

  # 支払い方法: 0:現金, 1:カード, 2:バーコード決済
  # 将来的に支払い方法が増えた場合はここに追記する
  enum :payment_method, { cash: 0, card: 1, barcode: 2 }

  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :receipt_number, presence: true, uniqueness: true

  before_validation :set_receipt_number, on: :create

  private

  def set_receipt_number
    return if receipt_number.present?

    # 企業識別子 (User.login_name)
    user_part = user&.login_name || "NO_USER"
    # 店舗識別子 (Store.ascii_name)
    store_part = store&.ascii_name || "NO_STORE"

    # POS端末が紐付いている場合（通常のPOS操作）は、連番ベースの番号を生成
    if pos_token.present?
      sequence = nil
      # トランザクション内でPOSトークンをロックし、安全にシーケンス番号を採番・更新
      # これにより、複数の会計が同時に発生しても番号の重複を防ぎます。
      pos_token.with_lock do
        sequence = pos_token.next_receipt_sequence
        pos_token.increment!(:next_receipt_sequence)
      end

      # 8桁ゼロ埋め
      sequence_part = sequence.to_s.rjust(8, '0')
      pos_part = pos_token.id

      # 新フォーマット: {企業Login名}-{店舗Ascii名}-{POS端末ID}-{連番}
      self.receipt_number = "#{user_part}-#{store_part}-#{pos_part}-#{sequence_part}"
    else
      # POS端末が紐付かない場合（Web管理画面からの手動登録など）は、
      # 競合しないように日時+ランダムベースの番号を生成
      time_part = Time.current.strftime("%Y%m%d%H%M%S")
      random_part = SecureRandom.alphanumeric(4).upcase
      pos_part = "MANUAL" # 手動操作であることがわかるように

      self.receipt_number = "#{user_part}-#{store_part}-#{pos_part}-#{time_part}-#{random_part}"
    end
  end
end
