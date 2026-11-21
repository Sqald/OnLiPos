# 「ログインしたままにする」Cookie によるログイン復元は、2段階認証を通過した後にのみ発行された Cookie なので、
# MFA 済みとして扱う（MfaSignIn#enforce_mfa_session がログアウトさせないよう印を付ける）。
# MFA 導入前に発行された Cookie はマイグレーション（remember_created_at のクリア）で無効化済み。
Warden::Manager.after_set_user except: :fetch do |record, warden, options|
  if options[:scope] == :user && record.is_a?(User) && warden.winning_strategy.is_a?(Devise::Strategies::Rememberable)
    warden.session(:user)[MfaSignIn::SESSION_MARK] = true
  end
end
