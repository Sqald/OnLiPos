# /home/sqald/github/OnLiPos/Server/onlipos/app/models/sale.rb

# 売上（会計1件）。明細は saledetails、支払い内訳は sale_payments、税率別内訳は
# sale_tax_breakdowns に持つ。確定後の取消はレコード削除ではなく status を voided にして記録する。
class Sale < ApplicationRecord
  # アソシエーション
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
  belongs_to :discount_approver, class_name: "Employee", optional: true

  belongs_to :customer, optional: true
  belongs_to :coupon, optional: true
  has_many :point_transactions, dependent: :restrict_with_exception

  # 電子レシートのURLに使う推測できない文字列
  before_create { self.public_token ||= SecureRandom.urlsafe_base64(24) }

  # 要確認の会計（オフライン会計の価格相違など）のうち、まだ確認していないもの
  scope :needing_review, -> { where("review_reasons <> '[]'::jsonb").where(reviewed_at: nil) }

  # 支払い方法（PaymentMethods を参照）
  enum :payment_method, PaymentMethods::VALUES

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

  # バリデーション
  validates :voided_at, :void_reason, presence: true, if: :voided?

  validates :total_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_discount, numericality: { greater_than_or_equal_to: 0 }
  validates :receipt_number, presence: true, uniqueness: true

  # コールバック
  before_validation :set_receipt_number, on: :create
  before_validation :set_accounting_dates, on: :create

  private

  # 集計はすべて business_date（営業日）基準のため、どの経路で作成されても必ず値を持たせる
  def set_accounting_dates
    self.sold_at ||= Time.current
    self.business_date ||= sold_at.in_time_zone.to_date
  end

  # 端末採番のレシート番号に合わせて、サーバーの次の連番を進める（戻すことはない）
  def advance_receipt_sequence
    return if pos_token.nil?

    match = receipt_number.match(/-(\d+)-(\d{8})\z/)
    return unless match && match[1].to_i == pos_token.id

    pos_token.with_lock do
      following = match[2].to_i + 1
      pos_token.update_columns(next_receipt_sequence: following) if following > pos_token.next_receipt_sequence
    end
  end

  # レシート番号を採番する（POS端末経由なら連番方式、手動登録なら日時+ランダム方式）
  def set_receipt_number
    # オフライン会計で端末が採番した番号は、サーバーの連番にも反映する。
    # 反映しないと、次のオンライン会計で同じ番号を払い出して登録できなくなる
    return advance_receipt_sequence if receipt_number.present?

    # 企業識別子 (User.login_name)
    user_part = user&.login_name || "NO_USER"
    # 店舗識別子 (Store.ascii_name)
    store_part = store&.ascii_name || "NO_STORE"

    # POS端末が紐付いている場合（通常のPOS操作）は、連番ベースの番号を生成
    if pos_token.present?
      # 新フォーマット: {企業Login名}-{店舗Ascii名}-{POS端末ID}-{8桁ゼロ埋めの連番}
      prefix = "#{user_part}-#{store_part}-#{pos_token.id}-"
      # POSトークンをロックし、同時会計でも番号が重複しないように採番する。
      # 使用済みの番号（過去に反映されなかったオフライン採番など）は飛ばす
      pos_token.with_lock do
        sequence = pos_token.next_receipt_sequence
        sequence += 1 while Sale.exists?(receipt_number: prefix + sequence.to_s.rjust(8, "0"))
        pos_token.update_columns(next_receipt_sequence: sequence + 1)
        self.receipt_number = prefix + sequence.to_s.rjust(8, "0")
      end
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
