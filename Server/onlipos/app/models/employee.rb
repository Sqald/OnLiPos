# 店舗スタッフ（POS端末の操作者）。PINでログインし、店舗ごとの権限（PERMISSION_CATALOG）で
# 操作可否を制御する。User（企業アカウント）に属し、複数 Store と多対多で関連する。
class Employee < ApplicationRecord
  MAX_FAILED_ATTEMPTS = 10
  UNLOCK_IN = 1.hour

  # 付与可能な権限の一覧（キー => 表示名）
  PERMISSION_CATALOG = {
    "open_register"  => "レジ開設",
    "close_register" => "レジ精算",
    "cash_check"     => "中間レジ金確認",
    "cash_pickup"    => "レジ金途中回収",
    "refund"         => "返品",
    "view_sales"     => "店舗売上閲覧",
    "edit_prices"    => "店舗価格編集",
    "view_journal"   => "ジャーナル閲覧",
    "inventory"      => "在庫操作",
    "discount"       => "値引き"
  }.freeze

  # アソシエーション
  belongs_to :user
  has_secure_password :pin, validations: false
  has_and_belongs_to_many :stores
  has_many :employee_permissions, dependent: :destroy

  # バリデーション
  validates :code, presence: true, uniqueness: { scope: :user_id }, length: { in: 1..12 }
  validates :pin, format: { with: /\A\d{4,6}\z/ }, allow_nil: true

  # 指定した権限キーを持っているかを判定する
  def permitted?(key)
    employee_permissions.exists?(permission: key.to_s)
  end

  # 付与済み権限キーの一覧を返す
  def permission_keys
    employee_permissions.pluck(:permission)
  end

  # 付与済み権限を desired_keys（PERMISSION_CATALOG のキーのみ）に同期する。
  # 差分のみ create/destroy するため無駄な DB 更新を避ける。
  def sync_permissions(desired_keys)
    desired = Array(desired_keys).map(&:to_s) & PERMISSION_CATALOG.keys
    current = employee_permissions.pluck(:permission)
    to_remove = current - desired
    to_add    = desired - current

    employee_permissions.where(permission: to_remove).destroy_all if to_remove.any?
    to_add.each { |k| employee_permissions.create!(permission: k) }
  end

  # 現在ロック中かどうかを判定する
  def access_locked?
    locked_at.present? && locked_at > UNLOCK_IN.ago
  end

  # ロックと失敗回数カウントを解除する
  def unlock_access!
    self.update_columns(failed_attempts: 0, locked_at: nil, updated_at: Time.current)
  end

  # PIN入力失敗回数を1つ増やし、上限に達したらロックする
  def increment_failed_attempts
    self.increment!(:failed_attempts)
    if failed_attempts >= MAX_FAILED_ATTEMPTS && !access_locked?
      self.update_column(:locked_at, Time.current)
    end
  end
end
