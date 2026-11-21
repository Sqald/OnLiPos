# ダッシュボードログインの多要素認証（MFA）を必須化するためのカラム・テーブル。
# - 認証アプリ（TOTP）: 秘密鍵は暗号化して保存し、同じコードの再利用を防ぐため最後に使ったタイムステップを記録する
# - パスキー（WebAuthn）: 1ユーザーが複数のパスキーを登録できる
# - リカバリーコード: 平文は保存せず SHA-256 ダイジェストのみを持つ（使い捨て）
# 既存の「ログインしたままにする」Cookie はパスワードのみで発行されたものなので、全件無効にする。
class AddMfaToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :otp_secret_ciphertext, :text
    add_column :users, :otp_enabled_at, :datetime
    add_column :users, :otp_last_used_timestep, :bigint
    add_column :users, :mfa_recovery_code_digests, :jsonb, default: [], null: false
    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true

    create_table :user_passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.string :nickname, null: false
      t.bigint :sign_count, default: 0, null: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :user_passkeys, :external_id, unique: true

    execute "UPDATE users SET remember_created_at = NULL"
  end

  def down
    drop_table :user_passkeys
    remove_index :users, :webauthn_id
    remove_column :users, :webauthn_id
    remove_column :users, :mfa_recovery_code_digests
    remove_column :users, :otp_last_used_timestep
    remove_column :users, :otp_enabled_at
    remove_column :users, :otp_secret_ciphertext
  end
end
