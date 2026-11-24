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
- **会員・販促**: ポイント、クーポン、自動値引き、電子レシート
- **仕入・棚卸・勤怠**: 発注、入荷、棚卸、打刻
- **飲食店向け**: 卓のQRコードからのセルフ注文、厨房画面、予約
- **税率変更の予約**: 適用日を指定して価格・税率を切り替え
- **安心の記録**: 2段階認証、操作履歴、書き換えられない電子ジャーナル

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
初回ログイン時に2段階認証（パスキーまたは認証アプリ）を登録します。

くわしい設定と、新しい版への更新手順は [SETUP.md](SETUP.md) を参照してください。

### HTTPS を有効にする（オプション）

SSL 証明書を用意して `Server/nginx/ssl/server.crt` と `Server/nginx/ssl/server.key` に配置し、`.env` で `FORCE_SSL=true` を設定してから再起動してください。

### エラー監視（Sentry、オプション）

[Sentry](https://sentry.io) の DSN を `.env` の `SENTRY_DSN` に設定するとエラー監視が有効になります。未設定でも問題ありません。

## クライアントアプリ（Flutter）

Windows 版は Microsoft Store からインストールできます。

<a href="https://get.microsoft.com/installer/download/9NB0GPXHFW0M?referrer=appbadge" target="_self">
  <img src="https://get.microsoft.com/images/ja%20dark.svg" width="200"/>
</a>

その他のプラットフォームはソースからビルドしてください。

```bash
cd Client/onlipos
flutter pub get
flutter run
```

## ライセンス

このソフトウェアは **MIT License** の下で公開されています。
詳細は `LICENSE` ファイルをご覧ください。
