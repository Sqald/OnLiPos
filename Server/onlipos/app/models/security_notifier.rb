# セキュリティ設定の変更を操作履歴に残す（セルフマネージド版にはメール機能がないため、通知はしない）
module SecurityNotifier
  def self.notify(user, event)
    AuditLog.record("security", target: user, details: { "操作" => event }, account: user.account, actor: user)
  end
end
