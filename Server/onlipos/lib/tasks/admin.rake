require 'io/console'

namespace :admin do
  desc "管理者アカウントを作成します (例: rails admin:create)"
  task create: :environment do
    print "管理者ユーザー名 (4〜32文字、英数字とアンダースコアのみ): "
    username = $stdin.gets.chomp

    if username.blank?
      abort "エラー: ユーザー名を入力してください。"
    end

    print "パスワード (12文字以上、大小英字・数字・記号を含む): "
    password = $stdin.noecho(&:gets).chomp
    puts

    if password.blank?
      abort "エラー: パスワードを入力してください。"
    end

    print "パスワード確認: "
    password_confirmation = $stdin.noecho(&:gets).chomp
    puts

    if password != password_confirmation
      abort "エラー: パスワードが一致しません。"
    end

    admin = Admin.new(
      username:              username,
      password:              password,
      password_confirmation: password_confirmation
    )

    if admin.save
      puts "✓ 管理者アカウント '#{username}' を作成しました。"
    else
      abort "エラー: #{admin.errors.full_messages.join(', ')}"
    end
  end

  desc "管理者パスワードを変更します (例: rails admin:change_password)"
  task change_password: :environment do
    print "管理者ユーザー名: "
    username = $stdin.gets.chomp

    admin = Admin.find_by("LOWER(username) = LOWER(?)", username.to_s.strip)
    abort "エラー: 管理者 '#{username}' が見つかりません。" unless admin

    print "新しいパスワード (12文字以上、大小英字・数字・記号を含む): "
    password = $stdin.noecho(&:gets).chomp
    puts

    print "新しいパスワード確認: "
    password_confirmation = $stdin.noecho(&:gets).chomp
    puts

    if password != password_confirmation
      abort "エラー: パスワードが一致しません。"
    end

    if admin.update(password: password, password_confirmation: password_confirmation)
      puts "✓ '#{username}' のパスワードを更新しました。"
    else
      abort "エラー: #{admin.errors.full_messages.join(', ')}"
    end
  end

  desc "管理者アカウント一覧を表示します"
  task list: :environment do
    admins = Admin.order(:created_at)
    if admins.empty?
      puts "管理者アカウントが登録されていません。"
      puts "  rails admin:create  で作成してください。"
    else
      printf "%-5s %-20s %-22s %-8s\n", "ID", "ユーザー名", "最終ログイン", "状態"
      puts "-" * 60
      admins.each do |a|
        last = a.last_sign_in_at&.strftime('%Y-%m-%d %H:%M') || "未ログイン"
        status = a.access_locked? ? "ロック中" : "正常"
        printf "%-5d %-20s %-22s %s\n", a.id, a.username, last, status
      end
    end
  end

  desc "管理者アカウントのロックを解除します (例: rails 'admin:unlock[username]')"
  task :unlock, [:username] => :environment do |_, args|
    username = args[:username] || begin
      print "管理者ユーザー名: "
      $stdin.gets.chomp
    end

    admin = Admin.find_by("LOWER(username) = LOWER(?)", username.to_s.strip)
    abort "エラー: 管理者 '#{username}' が見つかりません。" unless admin

    admin.unlock!
    puts "✓ '#{admin.username}' のロックを解除しました。"
  end

  desc "管理者アカウントを削除します (例: rails 'admin:delete[username]')"
  task :delete, [:username] => :environment do |_, args|
    username = args[:username] || begin
      print "管理者ユーザー名: "
      $stdin.gets.chomp
    end

    admin = Admin.find_by("LOWER(username) = LOWER(?)", username.to_s.strip)
    abort "エラー: 管理者 '#{username}' が見つかりません。" unless admin

    print "本当に '#{admin.username}' を削除しますか？ [y/N]: "
    confirm = $stdin.gets.chomp
    if confirm.downcase == 'y'
      admin.destroy!
      puts "✓ '#{username}' を削除しました。"
    else
      puts "キャンセルしました。"
    end
  end
end
