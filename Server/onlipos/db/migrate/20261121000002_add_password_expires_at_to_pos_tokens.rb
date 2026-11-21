# POS端末の初期パスワード（管理画面で生成）の有効期限。
# 端末がこのパスワードで認証を済ませると、パスワードは消去され期限も不要になる（端末のトークンは無期限）。
# 未認証のまま残っているパスワードには、本マイグレーション時点から2週間の期限を付ける。
class AddPasswordExpiresAtToPosTokens < ActiveRecord::Migration[8.1]
  def up
    add_column :pos_tokens, :password_expires_at, :datetime
    execute <<~SQL
      UPDATE pos_tokens SET password_expires_at = NOW() + INTERVAL '14 days'
       WHERE password_digest IS NOT NULL
    SQL
  end

  def down
    remove_column :pos_tokens, :password_expires_at
  end
end
