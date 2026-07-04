# 電子ジャーナルのハッシュチェーン検証。
# 連番の欠番・重複、previous_hash の不整合、エントリ本体の改変を検知する。
# 使い方: bin/rails journal:verify
namespace :journal do
  desc "全端末のジャーナルのハッシュチェーンを検証する"
  task verify: :environment do
    total_issues = 0

    PosToken.find_each do |pos_token|
      issues = JournalEntry.verify_chain(pos_token)
      next if issues.empty?

      total_issues += issues.size
      puts "POS ##{pos_token.id} (#{pos_token.name}):"
      issues.each { |issue| puts "  #{issue}" }
    end

    if total_issues.zero?
      puts "OK: すべてのジャーナルチェーンは健全です"
    else
      abort "NG: #{total_issues} 件の不整合が見つかりました"
    end
  end
end
