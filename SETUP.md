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

- `SECRET_KEY_BASE`: 必須（未設定だと Rails が起動できません）
- `HOST_NAME`: アクセスに使うホスト名（未設定でも動作します）
- `DB_USER` / `DB_NAME`
- `FORCE_SSL`: HTTPS で運用する場合は `true`
- `BACKUP_*`: バックアップの暗号化・外部保管・通知（任意。`sample.env` の説明を参照）

`SECRET_KEY_BASE` は以下で生成できます:

```bash
openssl rand -hex 64
```

生成した文字列を `.env` の `SECRET_KEY_BASE` に設定してください。

## 3. Docker secrets の準備

`Server/secrets/db_password.txt` に PostgreSQL のパスワードを1行で設定します。

```bash
printf 'your-db-password\n' > secrets/db_password.txt
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

- はじめに「新規登録」でアカウントを作成します。ログインには2段階認証（パスキーまたは認証アプリ）の登録が必要です。
- ログイン後、ホームの「はじめの準備」に沿って、店舗・商品・従業員・POS端末を登録します。

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

## 7. 新しい版への更新

1. 更新の前に、データベースを手動でバックアップします。
   `docker compose exec postgres sh -c 'pg_dump -U "$POSTGRES_USER" -Fc <DB_NAME>_prod' > backup.dump`
2. `git pull` のあと `docker compose up -d --build` を実行します（DBの変更は自動で適用されます）。
3. **サーバーを先に、端末アプリを後に**更新します。未送信の会計がある端末は、先に送信してください。
4. 旧版の端末が残る間だけ `.env` で `ALLOW_LEGACY_OPERATOR_AUTH=true` にします。
   有効な間は PIN による本人確認が強制されないため、端末の更新が終わったら必ず空に戻し、`MIN_APP_VERSION` を設定してください。
5. バックアップから復元できることを確認します。`docker compose exec backup sh /scripts/restore_test.sh`

1.0 系から更新した場合、管理者は次回ログイン時に2段階認証の登録が必要です。DBを以前の状態へ戻すと、全端末の再認証が必要になります。
Android 版はアプリIDが変わったため、入れ直しになります。

## 8. 補足（Public版の認証方針）

この Public リポジトリはセルフマネージド運用向けのため、メール機能（メールアドレスの確認・パスワード再設定メールなど）はありません。
2段階認証が使えなくなった場合は、サーバー管理者が次のコマンドでリセットします。

```bash
docker compose exec rails bin/rails "mfa:reset[ログイン名]"
```
