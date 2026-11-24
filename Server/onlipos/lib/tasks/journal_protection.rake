# ジャーナル保護トリガーを、スキーマの読み込み・移行の後に必ず作成する
namespace :journal do
  desc "ジャーナルの追記専用トリガーを作成する"
  task protect: :environment do
    JournalProtection.install!
  end
end

%w[db:migrate db:schema:load db:prepare db:test:load_schema].each do |name|
  Rake::Task[name].enhance do
    next if ActiveRecord::Base.connection_pool.nil?

    configs = [ ActiveRecord::Base.connection_db_config ]
    configs = ActiveRecord::Base.configurations.configs_for(env_name: "test", name: "primary").then { |c| [ c ].compact } if name == "db:test:load_schema"
    configs.each do |config|
      ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) { |connection| JournalProtection.install!(connection) }
    end
  end
end
