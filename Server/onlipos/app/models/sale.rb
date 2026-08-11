# /home/sqald/github/OnLiPos/Server/onlipos/app/models/sale.rb

# 売上（会計1件）。明細は saledetails、支払い内訳は sale_payments、税率別内訳は
# sale_tax_breakdowns に持つ。確定後の取消はレコード削除ではなく status を voided にして記録する。
class Sale < ApplicationRecord
  belongs_to :user
  belongs_to :store
  belongs_to :pos_token, optional: true
  belongs_to :employee, optional: true
  belongs_to :register_session, optional: true
  belongs_to :voided_by_employee, class_name: "Employee", optional: true
  has_many :saledetails, dependent: :destroy
  has_many :sale_payments, dependent: :destroy
  has_many :sale_tax_breakdowns, dependent: :destroy
  has_many :refunds, dependent: :restrict_with_exception

  # 支払い方法: 0:現金, 1:カード, 2:バーコード決済, 3:電子マネー
  # 将来的に支払い方法が増えた場合はここに追記する
  enum :payment_method, { cash: 0, card: 1, barcode: 2, emoney: 3 }

  # 0: 有効な売上, 1: 確定後取消（VOID）。取消は削除ではなく状態遷移で記録する
  enum :status, { completed: 0, voided: 1 }

  # 小計割引の種別（0: 金額, 1: パーセント）。NULL は割引なし
  enum :order_discount_type, { amount: 0, percent: 1 }, prefix: :order_discount

  # 客層キー（東芝テック製レジ等に見られる、性別・年代による匿名の客層データ収集）。NULLは未選択（任意入力）
  enum :customer_gender, { male: 0, female: 1, other: 2 }, prefix: true
  enum :customer_age_group, {
    under19: 0,
    twenties: 1,
    thirties: 2,
    forties: 3,
    fifties: 4,
    sixty_plus: 5
  }, prefix: true

  validates :voided_at, :void_reason, presence: true, if: :voided?

  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_discount, numericality: { greater_than_or_equal_to: 0 }
  validates :receipt_number, presence: true, uniqueness: true

  before_validation :set_receipt_number, on: :create
  before_validation :set_accounting_dates, on: :create

  private

  # 集計はすべて business_date（営業日）基準のため、どの経路で作成されても必ず値を持たせる
  def set_accounting_dates
    self.sold_at ||= Time.current
    self.business_date ||= sold_at.in_time_zone.to_date
  end

  # レシート番号を採番する（POS端末経由なら連番方式、手動登録なら日時+ランダム方式）
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
      sequence_part = sequence.to_s.rjust(8, "0")
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
