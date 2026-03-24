#!/bin/sh

CERT_FILE="/ssl/server.crt"
KEY_FILE="/ssl/server.key"
CONF_FILE="/etc/nginx/conf.d/ssl_settings.generated"

if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
    echo "SSL証明書が見つかりました。HTTPS (443) を有効にします。"
    # 設定ファイルに中身を書き込む
    cat <<EOF > $CONF_FILE
    listen 443 ssl;
    ssl_certificate $CERT_FILE;
    ssl_certificate_key $KEY_FILE;
    # その他SSL設定が必要ならここに追加
EOF
else
    echo "SSL証明書がありません。HTTP (80) のみで起動します。"
    echo "" > $CONF_FILE
fi