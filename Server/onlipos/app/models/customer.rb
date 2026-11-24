# 会員。ポイント残高と掛売残高を持ち、増減は必ず履歴とあわせて記録する。
class Customer < ApplicationRecord
  include Auditable
  class InsufficientPoints < StandardError; end
  class CreditNotAllowed < StandardError; end

  belongs_to :user
  has_many :sales, dependent: :restrict_with_error
  has_many :point_transactions, dependent: :restrict_with_error
  has_many :receivable_transactions, dependent: :restrict_with_error
  has_many :reservations, dependent: :nullify

  before_validation :assign_code, on: :create

  validates :code, presence: true, uniqueness: { scope: :user_id }, length: { maximum: 32 }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :active, -> { where(anonymized_at: nil) }

  def self.search(term)
    return all if term.blank?

    like = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("code ILIKE :q OR name ILIKE :q OR phone LIKE :q", q: like)
  end

  # ポイントを増減し、履歴を残す。残高は負にならない
  def add_points!(amount, kind:, sale: nil, refund: nil, note: nil, floor: false)
    return if amount.zero?

    with_lock do
      amount = -points if floor && points + amount < 0
      raise InsufficientPoints, "ポイントが不足しています（残高 #{points}）" if points + amount < 0

      update_columns(points: points + amount, updated_at: Time.current)
      point_transactions.create!(kind: kind, points: amount, balance: points, sale: sale, refund: refund, note: note) unless amount.zero?
    end
  end

  def add_receivable!(amount, sale: nil, refund: nil, note: nil)
    return if amount.zero?

    with_lock do
      raise CreditNotAllowed, "この会員は掛売を利用できません" if amount.positive? && !credit_allowed

      update_columns(receivable: receivable + amount, updated_at: Time.current)
      receivable_transactions.create!(amount: amount, balance: receivable, sale: sale, refund: refund, note: note)
    end
  end

  # 会員本人からの削除請求への対応。取引記録は残し、個人を特定できる情報だけを消す
  def anonymize!
    update!(name: "退会済み会員", phone: nil, email: nil, birthday: nil, note: nil, credit_allowed: false, anonymized_at: Time.current)
  end

  private

  def assign_code
    return if code.present?

    self.code = loop do
      candidate = "M#{SecureRandom.random_number(10**9).to_s.rjust(9, '0')}"
      break candidate unless Customer.exists?(user_id: user_id, code: candidate)
    end
  end
end
