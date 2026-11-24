# 契約アカウントの操作履歴（マスタ・価格・権限・在庫・端末・メンバーなどの変更）。
# ダッシュボードの利用者、またはPOS端末＋担当者による変更を Auditable から記録する。
class AuditLog < ApplicationRecord
  belongs_to :user

  # 追記のみ
  def readonly? = persisted?

  ACTION_LABELS = {
    "create" => "登録", "update" => "変更", "destroy" => "削除", "sign_in" => "ログイン", "export" => "出力",
    "review" => "確認", "view" => "閲覧", "apply" => "反映", "security" => "セキュリティ設定"
  }.freeze

  TARGET_LABELS = {
    "Product" => "商品", "Price" => "店舗価格", "ProductCategory" => "カテゴリ", "ProductBundle" => "セット商品", "Employee" => "従業員",
    "EmployeePermission" => "従業員の権限", "Store" => "店舗", "PosToken" => "POS端末", "Provisioning" => "端末設定", "User" => "アカウント",
    "StoreStock" => "在庫", "Sale" => "会計",
    "OptionGroup" => "オプション", "Customer" => "会員", "Coupon" => "クーポン", "Promotion" => "自動値引き", "Supplier" => "仕入先",
    "PurchaseOrder" => "発注", "Stocktake" => "棚卸", "ApiKey" => "APIキー", "Webhook" => "Webhook"
  }.freeze

  def action_label = ACTION_LABELS.fetch(action, action)

  def target_label = TARGET_LABELS.fetch(target_type.to_s, target_type)

  # 記録する。Current.account がない処理（コンソール・移行など）では何もしない。
  # 記録の失敗で本来の処理を止めない
  def self.record(action, target: nil, details: {}, account: Current.account, actor: Current.actor)
    return if account.nil?

    transaction(requires_new: true) do
      create!(
        user: account, actor_type: actor&.class&.name, actor_id: actor&.id, actor_name: actor_name(actor),
        action: action.to_s, target_type: target&.class&.name, target_id: target&.id,
        target_name: target.respond_to?(:audit_name) ? target.audit_name : target.try(:name),
        details: details, ip_address: Current.ip_address
      )
    end
  rescue => e
    Rails.logger.error "[AuditLog] Failed to record: #{e.class} #{e.message}"
    Sentry.capture_exception(e) if defined?(Sentry)
  end

  def self.actor_name(actor)
    case actor
    when User then actor.display_name
    when PosToken then "端末 #{actor.name}"
    else actor.try(:name)
    end
  end
end
