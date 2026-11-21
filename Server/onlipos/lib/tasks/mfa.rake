namespace :mfa do
  desc "ユーザーの2段階認証をリセットします（端末とリカバリーコードを紛失した場合。本人確認後に実施）例: rails \"mfa:reset[login_name]\""
  task :reset, [ :login_name ] => :environment do |_task, args|
    login_name = args[:login_name].to_s.strip
    abort "エラー: ログイン名を指定してください（例: rails \"mfa:reset[shop01]\"）" if login_name.blank?

    user = User.find_by("LOWER(login_name) = ?", login_name.downcase)
    abort "エラー: ユーザー「#{login_name}」が見つかりません。" unless user

    user.reset_mfa!
    puts "#{user.login_name}（#{user.email}）の2段階認証をリセットしました。次回ログイン時に再設定が必要です。"
  end
end
