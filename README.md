# OnLiPos - セルフホスト型 POS レジシステム

<p align="center">
  <img src="Logo/Logo_1000x1000.png" alt="OnLiPos Logo" width="250"/>
</p>

`OnLiPos` は、パソコンやタブレットで使える、セルフホスト型のオープンソース POS レジシステムです。
自分のサーバーで動かせるので、データはすべて手元で管理できます。

## 主な機能

- **かんたん会計**: 直感的な操作で誰でも使える販売画面
- **商品管理**: 写真付き商品情報の登録
- **在庫管理**: 店舗ごとのリアルタイム在庫把握
- **従業員管理**: スタッフごとのアクセス権限設定
- **複数店舗対応**: すべての店舗の売上・在庫を一元管理
- **売上分析**: Web ダッシュボードで売上確認
- **オフライン対応**: 通信障害時も会計継続、復帰後に自動同期

## セットアップ（Docker Compose）

### 必要なもの

- Docker + Docker Compose
- git

### 手順

```bash
# 1. クローン
git clone https://github.com/Sqald/OnLiPos.git
cd OnLiPos/Server

# 2. 環境変数ファイルを作成
cp sample.env .env
# .env を編集して SECRET_KEY_BASE を設定してください
# SECRET_KEY_BASE は openssl rand -hex 64 などで生成できます

# 3. DB パスワードを設定
echo "任意の安全なパスワード" > secrets/db_password.txt

# 4. 起動
docker-compose up -d
```

ブラウザで `http://サーバーのIP` にアクセスし、アカウントを作成してください。

### HTTPS を有効にする（オプション）

SSL 証明書を用意して `Server/nginx/ssl/server.crt` と `Server/nginx/ssl/server.key` に配置し、`.env` で `FORCE_SSL=true` を設定してから再起動してください。

### エラー監視（Sentry、オプション）

[Sentry](https://sentry.io) の DSN を `.env` の `SENTRY_DSN` に設定するとエラー監視が有効になります。未設定でも問題ありません。

## クライアントアプリ（Flutter）

```bash
cd Client/onlipos
flutter pub get
flutter run
```

## ライセンス

このソフトウェアは **MIT License** の下で公開されています。
詳細は `LICENSE` ファイルをご覧ください。
