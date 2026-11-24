# アカウント・端末のセキュリティ強化
# - 管理者（コントロールセンター）の2段階認証
# - セッションの一括無効化（session_version）と契約者の利用停止（suspended_at）
# - 端末トークンはダイジェストのみ保存し、端末の遠隔停止・アプリのバージョン記録に対応する
class HardenAccountsAndTerminals < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:admins)
      change_table :admins, bulk: true do |t|
        t.text :otp_secret_ciphertext
        t.datetime :otp_enabled_at
        t.bigint :otp_last_used_timestep
        t.integer :session_version, null: false, default: 0
      end
    end

    change_table :users, bulk: true do |t|
      t.integer :session_version, null: false, default: 0
      t.datetime :suspended_at
      t.string :suspended_reason
    end

    change_table :pos_tokens, bulk: true do |t|
      t.string :token_digest
      t.datetime :disabled_at
      t.string :disabled_reason
      t.string :app_version
      t.string :platform
      t.string :last_ip
    end
    execute "UPDATE pos_tokens SET token_digest = encode(sha256(token::bytea), 'hex') WHERE token IS NOT NULL"
    add_index :pos_tokens, :token_digest, unique: true
    remove_index :pos_tokens, :token
    remove_column :pos_tokens, :token
  end

  # 平文トークンは復元できないため、ロールバック後は各端末で再ログイン（パスワード再発行）が必要
  def down
    add_column :pos_tokens, :token, :string
    add_index :pos_tokens, :token, unique: true
    remove_columns :pos_tokens, :token_digest, :disabled_at, :disabled_reason, :app_version, :platform, :last_ip
    remove_columns :users, :session_version, :suspended_at, :suspended_reason
    remove_columns :admins, :otp_secret_ciphertext, :otp_enabled_at, :otp_last_used_timestep, :session_version if table_exists?(:admins)
  end
end
