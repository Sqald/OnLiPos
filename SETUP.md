# OnLiPos Public セルフマネージドセットアップ

このドキュメントは `OnLiPos_Public` をセルフマネージド環境で動かすための最短手順です。  
対象は主に `Server/`（Rails + PostgreSQL + Nginx）です。

## 1. 前提条件

- Docker / Docker Compose が使えること
- 80/443 ポートを利用できること
- `git` でこのリポジトリを取得済みであること

## 2. サーバ設定ファイルの準備

`Server/` に移動して、環境変数ファイルを作成します。

```bash
cd Server
cp sample.env .env
```

`.env` で最低限見直す項目:

- `HOST_NAME`: 運用するホスト名 or IP
- `HOST_PORT`: 通常 `80`
- `DB_USER` / `DB_NAME`
- `SECRET_KEY_BASE`: 必須（未設定だと Rails が起動できません）
- `SMTP_ADDRESS` / `SMTP_PORT` / `SMTP_USER_NAME` / `SMTP_MAIL_ADDRESS` / `SMTP_DOMAIN`（通知メールを使う場合）

`SECRET_KEY_BASE` は以下で生成できます:

```bash
docker compose run --rm rails bin/rails secret
```

生成した文字列を `.env` の `SECRET_KEY_BASE` に設定してください。

## 3. Docker secrets の準備

`Server/secrets/` に以下2ファイルを作成します。

- `db_password.txt`: PostgreSQL のパスワード（1行）
- `smtp_password.txt`: SMTP パスワード（1行）

例:

```bash
mkdir -p secrets
printf 'your-db-password\n' > secrets/db_password.txt
printf 'your-smtp-password\n' > secrets/smtp_password.txt
```

## 4. 起動

`Server/` で実行:

```bash
docker compose up -d --build
```

初回起動時に Rails コンテナで `db:prepare` が実行され、DB作成・マイグレーションが自動で行われます。

## 5. アクセス確認

- `http://<HOST_NAME>`（または `http://localhost`）
- SSL証明書を `Server/nginx/ssl/server.crt` と `Server/nginx/ssl/server.key` に配置すると、起動時に HTTPS (443) が有効になります。

## 6. よく使う運用コマンド

```bash
# ログ確認
docker compose logs -f rails
docker compose logs -f nginx

# 停止
docker compose down

# イメージ更新を含めて再起動
docker compose up -d --build
```

## 7. 補足（Public版の認証方針）

この Public リポジトリはセルフマネージド運用向けのため、メール確認（Confirmable）なしの構成を前提としています。  
ただし、パスワード再設定メールなどを使う場合は SMTP 設定が必要です。
