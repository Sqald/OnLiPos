#!/bin/sh
# 復元テスト: 最新（または指定した）バックアップを使い捨てDBへ復元し、件数を表示して削除する。
#   docker compose exec backup sh /scripts/restore_test.sh [ファイル名]
#
# 実際の復元（障害時）:
#   1. 必要なら復号: openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass file:/run/backup-secrets/backup_passphrase.txt -in X.dump.enc -out X.dump
#   2. docker compose stop rails worker
#   3. 空のDBを作成: createdb -h postgres -U "$DB_USER" <新DB名>
#   4. pg_restore -h postgres -U "$DB_USER" -d <新DB名> --no-owner --exit-on-error X.dump
#   5. 件数を確認してからDB名を入れ替え（ALTER DATABASE ... RENAME）、rails / worker を起動
set -eu
export PGPASSWORD="$(cat /run/secrets/db_password)" PGHOST="${BACKUP_HOST:-postgres}" PGUSER="$DB_USER"
umask 077

file="${1:-$(ls -1t /backup/onlipos_2*.dump* 2>/dev/null | head -1)}"
[ -n "$file" ] || { echo "バックアップがありません"; exit 1; }
case "$file" in /*) ;; *) file="/backup/$file" ;; esac

db="restore_test_$$"
work="$(mktemp)"
cleanup() { rm -f "$work"; dropdb --if-exists "$db" >/dev/null 2>&1 || true; }
trap cleanup EXIT

case "$file" in
  *.enc) openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass file:/run/backup-secrets/backup_passphrase.txt -in "$file" -out "$work" ;;
  *) cp "$file" "$work" ;;
esac

createdb "$db"
pg_restore -d "$db" --no-owner --exit-on-error "$work"
echo "復元できました: $file"
psql -d "$db" -At -F ' : ' -c "
  SELECT 'users', count(*) FROM users UNION ALL
  SELECT 'stores', count(*) FROM stores UNION ALL
  SELECT 'sales', count(*) FROM sales UNION ALL
  SELECT 'journal_entries', count(*) FROM journal_entries UNION ALL
  SELECT '最終の売上', extract(epoch from max(created_at))::bigint FROM sales"
