# 電子ジャーナル（journal_entries）を、アプリ外からのSQLも含めて追記専用にするDBトリガー。
# schema.rb はトリガーを保存できないため、db:migrate / db:prepare / db:schema:load の後に毎回作成する（冪等）。
#
# 店舗の削除（取引のない店舗のみ可能）など、正当な保守では JournalProtection.allow を使う。
module JournalProtection
  SETTING = "onlipos.journal_maintenance".freeze

  def self.install!(connection = ActiveRecord::Base.connection)
    return unless connection.table_exists?(:journal_entries)

    connection.execute(<<~SQL)
      CREATE OR REPLACE FUNCTION onlipos_protect_journal() RETURNS trigger AS $$
      BEGIN
        IF current_setting('#{SETTING}', true) = 'on' THEN
          IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
          RETURN NEW;
        END IF;
        RAISE EXCEPTION 'journal_entries is append-only (% denied)', TG_OP;
      END;
      $$ LANGUAGE plpgsql;

      DROP TRIGGER IF EXISTS journal_entries_append_only ON journal_entries;
      CREATE TRIGGER journal_entries_append_only
        BEFORE UPDATE OR DELETE ON journal_entries
        FOR EACH ROW EXECUTE FUNCTION onlipos_protect_journal();

      DROP TRIGGER IF EXISTS journal_entries_no_truncate ON journal_entries;
      CREATE TRIGGER journal_entries_no_truncate
        BEFORE TRUNCATE ON journal_entries
        FOR EACH STATEMENT EXECUTE FUNCTION onlipos_protect_journal();
    SQL
  end

  def self.uninstall!(connection = ActiveRecord::Base.connection)
    connection.execute(<<~SQL)
      DROP TRIGGER IF EXISTS journal_entries_append_only ON journal_entries;
      DROP TRIGGER IF EXISTS journal_entries_no_truncate ON journal_entries;
      DROP FUNCTION IF EXISTS onlipos_protect_journal();
    SQL
  end

  # ブロック内（トランザクション内）に限り、ジャーナルの削除・更新を許可する
  def self.allow
    ActiveRecord::Base.transaction do
      connection = ActiveRecord::Base.connection
      connection.execute("SET LOCAL #{SETTING} = 'on'")
      result = yield
      connection.execute("SET LOCAL #{SETTING} = 'off'")
      result
    end
  end
end
