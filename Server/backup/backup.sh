#!/bin/sh
# 本番DB（primary）を定期的にダンプし、復元できる内容かを確認してから保存する。
#
#   /backup/onlipos_YYYYmmdd_HHMMSS.dump[.enc]  … pg_dump カスタム形式（暗号化時は .enc）
#   /backup/LAST_SUCCESS                        … 最終成功時刻（healthcheck が参照）
#
# 環境変数:
#   BACKUP_DB              ダンプ対象のDB名（必須。production.primary と同じ "<DB_NAME>_prod"）
#   BACKUP_INTERVAL        実行間隔（秒、既定 86400）
#   BACKUP_RETENTION_DAYS  保存日数（既定 30）
#   BACKUP_OFFSITE_DIR     2か所目の保存先ディレクトリ（NAS等をマウントして指定。任意）
#   BACKUP_WEBHOOK_URL     失敗時に通知するURL（任意。JSONをPOST）
#   secrets/backup_passphrase.txt（/run/backup-secrets/backup_passphrase.txt）があれば AES-256 で暗号化する
set -eu

: "${BACKUP_DB:?BACKUP_DB を指定してください}"
DIR=/backup
PASS_FILE=/run/backup-secrets/backup_passphrase.txt
export PGPASSWORD="$(cat /run/secrets/db_password)"
umask 077

log() { echo "[backup] $(date '+%F %T') $*"; }

notify_failure() {
  log "失敗: $1"
  [ -n "${BACKUP_WEBHOOK_URL:-}" ] || return 0
  # postgres イメージには curl が無いため、あるコマンドを使う
  body="{\"text\":\"OnLiPos バックアップ失敗: $1\"}"
  if command -v curl >/dev/null; then
    curl -fsS -m 20 -H 'Content-Type: application/json' -d "$body" "$BACKUP_WEBHOOK_URL" >/dev/null || true
  elif command -v wget >/dev/null; then
    wget -q -T 20 -O /dev/null --header 'Content-Type: application/json' --post-data "$body" "$BACKUP_WEBHOOK_URL" || true
  elif command -v perl >/dev/null; then
    perl -MHTTP::Tiny -e 'HTTP::Tiny->new(timeout=>20)->post($ARGV[0],{headers=>{"Content-Type"=>"application/json"},content=>$ARGV[1]})' "$BACKUP_WEBHOOK_URL" "$body" || true
  fi
}

run_once() {
  name="onlipos_$(date +%Y%m%d_%H%M%S).dump"
  tmp="$DIR/.$name.tmp"
  rm -f "$DIR"/.*.tmp

  pg_dump -h "${BACKUP_HOST:-postgres}" -U "$DB_USER" -d "$BACKUP_DB" --format=custom --no-owner -f "$tmp" || { notify_failure "pg_dump がエラーになりました"; return 1; }

  # 中身の確認: 主要テーブルのデータが含まれていること（空のDBを保存し続ける事故を防ぐ）
  list="$(pg_restore --list "$tmp")" || { notify_failure "ダンプを読み取れません"; return 1; }
  for table in users stores sales saledetails journal_entries; do
    echo "$list" | grep -q "TABLE DATA public $table " || { notify_failure "ダンプに $table が含まれていません"; rm -f "$tmp"; return 1; }
  done

  if [ -s "$PASS_FILE" ]; then
    openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt -pass "file:$PASS_FILE" -in "$tmp" -out "$tmp.enc" || { notify_failure "暗号化に失敗しました"; return 1; }
    rm -f "$tmp"; tmp="$tmp.enc"; name="$name.enc"
  fi

  mv "$tmp" "$DIR/$name"
  if [ -n "${BACKUP_OFFSITE_DIR:-}" ]; then
    cp "$DIR/$name" "$BACKUP_OFFSITE_DIR/.$name.tmp" && mv "$BACKUP_OFFSITE_DIR/.$name.tmp" "$BACKUP_OFFSITE_DIR/$name" \
      || notify_failure "2か所目への保存に失敗しました"
  fi

  # 商品画像などの添付ファイル（DBとは別に保存されている）
  if [ -d /storage ]; then
    files="onlipos_storage_$(date +%Y%m%d_%H%M%S).dump.tar.gz"
    if tar -C /storage -czf "$DIR/.$files.tmp" . && mv "$DIR/.$files.tmp" "$DIR/$files"; then
      [ -z "${BACKUP_OFFSITE_DIR:-}" ] || cp "$DIR/$files" "$BACKUP_OFFSITE_DIR/$files" || notify_failure "添付ファイルの2か所目への保存に失敗しました"
    else
      notify_failure "添付ファイルの保存に失敗しました"
    fi
  fi

  # 新しいバックアップが成功したときだけ古いものを消す
  for d in "$DIR" ${BACKUP_OFFSITE_DIR:-}; do
    find "$d" -maxdepth 1 -name 'onlipos_*.dump*' -mtime "+${BACKUP_RETENTION_DAYS:-30}" -delete
  done
  date +%s > "$DIR/LAST_SUCCESS"
  log "成功: $name ($(wc -c < "$DIR/$name") bytes)"
}

case "${1:-loop}" in
  once) run_once ;;
  loop)
    while true; do
      run_once || true
      sleep "${BACKUP_INTERVAL:-86400}"
    done ;;
esac
