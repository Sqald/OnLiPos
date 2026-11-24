# リクエスト単位の「誰が・どのアカウントで・どこから」。操作履歴（AuditLog）の記録に使う。
class Current < ActiveSupport::CurrentAttributes
  attribute :account, :actor, :ip_address
end
