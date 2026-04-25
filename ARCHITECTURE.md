# OnLiPos システム アーキテクチャ ドキュメント

## 目次

1. [システム概要](#1-システム概要)
2. [技術スタック](#2-技術スタック)
3. [インフラ構成](#3-インフラ構成)
4. [サーバー側 — データベース設計](#4-サーバー側--データベース設計)
5. [サーバー側 — モデル層](#5-サーバー側--モデル層)
6. [サーバー側 — API コントローラー](#6-サーバー側--api-コントローラー)
7. [サーバー側 — ダッシュボード コントローラー](#7-サーバー側--ダッシュボード-コントローラー)
8. [サーバー側 — ルーティング](#8-サーバー側--ルーティング)
9. [サーバー側 — バックグラウンドジョブ](#9-サーバー側--バックグラウンドジョブ)
10. [クライアント側 — アプリ起動フロー](#10-クライアント側--アプリ起動フロー)
11. [クライアント側 — 機能別モジュール](#11-クライアント側--機能別モジュール)
12. [クライアント側 — ローカルデータ管理](#12-クライアント側--ローカルデータ管理)
13. [クライアント側 — ESC/POS レシート印刷](#13-クライアント側--escpos-レシート印刷)
14. [認証・セキュリティ設計](#14-認証セキュリティ設計)
15. [オフライン対応設計](#15-オフライン対応設計)
16. [店舗モード（飲食店 / 小売店 / 標準）](#16-店舗モード飲食店--小売店--標準)
17. [ホスト・クライアント型 POS モード](#17-ホストクライアント型-pos-モード)
18. [データフロー — 売上登録](#18-データフロー--売上登録)
19. [データフロー — 返品処理](#19-データフロー--返品処理)
20. [データフロー — 在庫管理](#20-データフロー--在庫管理)
21. [設計上の重要パターン](#21-設計上の重要パターン)

---

## 1. システム概要

**OnLiPos** はクラウドベースの POS（Point of Sale）システムです。

```
┌───────────────────────────────────────────────────────┐
│                    クラウドサーバー                      │
│  ┌──────────────┐   ┌──────────────┐  ┌────────────┐  │
│  │ Rails API    │   │ Web Dashboard│  │ PostgreSQL │  │
│  │ /api/v1/*    │   │ /dashboard/* │  │            │  │
│  └──────────────┘   └──────────────┘  └────────────┘  │
│          ↑                  ↑                          │
│        Nginx (80/443) リバースプロキシ                   │
└───────────────────────────────────────────────────────┘
         ↑                          ↑
         │ HTTPS                    │ ブラウザ (HTTPS)
         │
┌────────────────────────────────────┐
│        Flutter POS クライアント     │
│  Android / iOS / Windows / macOS  │
│  Linux / Web                      │
│                                   │
│  ローカル SQLite（商品・オフライン売上） │
│  FlutterSecureStorage（認証トークン）  │
└────────────────────────────────────┘
```

**主な機能:**
- 複数店舗・複数 POS 端末対応
- 商品マスタ管理（CSV 一括インポート）
- 売上登録・レシート印刷（ESC/POS LAN 接続）
- 返品処理（二重承認）
- 在庫管理（入出庫・店舗間移動）
- レジ開設・中間金庫確認・精算
- 飲食店モード（卓番管理）・小売店モード（保留管理）
- **ホスト・クライアント型 POS**（タブレットで商品登録 → レジカウンターに転送して会計）
- オフライン時の売上キューイング

---

## 2. 技術スタック

### サーバー

| 要素 | 内容 |
|------|------|
| フレームワーク | Ruby on Rails 8.1.2 |
| データベース | PostgreSQL |
| 認証 | Devise（ユーザー）+ has_secure_token（POS 端末）+ has_secure_password（従業員 PIN） |
| バックグラウンドジョブ | Solid Queue |
| キャッシュ | Solid Cache |
| ページネーション | Kaminari |
| Web サーバー | Puma |
| リバースプロキシ | Nginx |
| セキュリティ監査 | Brakeman、bundler-audit |
| コーディング規約 | RuboCop |

### クライアント

| 要素 | 内容 |
|------|------|
| フレームワーク | Flutter（Dart） |
| プラットフォーム | Android、iOS、Windows、macOS、Linux、Web |
| ローカル DB | sqflite（モバイル）/ sqflite_common_ffi（デスクトップ） |
| 安全なストレージ | flutter_secure_storage |
| HTTP クライアント | http パッケージ |
| バーコードスキャン | mobile_scanner |
| 文字コード変換 | charset_converter（ESC/POS Shift_JIS 対応） |
| ウィンドウ管理 | window_manager（デスクトップ キオスクモード） |

---

## 3. インフラ構成

### Docker Compose 構成

**`Server/docker-compose.yml`**

3 つのコンテナで構成されます：

```
┌─────────────────────────────────────────────────┐
│  nginx コンテナ                                  │
│  ポート 80 (HTTP) / 443 (HTTPS)                 │
│  SSL 証明書: /nginx/ssl/                        │
│  → upstream: http://rails:3000/                 │
└────────────────────┬────────────────────────────┘
                     │
        ┌────────────▼────────────┐
        │  rails コンテナ         │
        │  Puma :3000             │
        │  depends_on: postgres   │
        └────────────┬────────────┘
                     │
        ┌────────────▼────────────┐
        │  postgres コンテナ      │
        │  パスワード: secrets/   │
        │  ヘルスチェックあり     │
        └────────────────────────┘
```

**環境変数・シークレット管理:**
- 環境変数: `Server/.env`（`Server/sample.env` を参考に作成）
- DB パスワード: `Server/secrets/db_password.txt`
- SMTP パスワード: `Server/secrets/smtp_password.txt`
- どちらも `.gitignore` で除外済み（`Server/secrets/*`）

### Nginx 設定

- HTTP→HTTPS リダイレクト（ポート 80 → 443）
- SSL termination
- `X-Real-IP`、`X-Forwarded-For`、`X-Forwarded-Proto` ヘッダーを Rails へ転送

### CI/CD（GitHub Actions）

**`.github/workflows/ci.yml`**

プッシュ・プルリクエスト時に以下を自動実行：

1. `bin/brakeman --no-pager` — セキュリティ脆弱性スキャン
2. `bin/bundler-audit` — Gem 依存関係の CVE チェック
3. `bin/rubocop -f github` — コーディング規約チェック
4. `bin/rails test` — 全ユニット・結合テスト

---

## 4. サーバー側 — データベース設計

### ER 図（概略）

```
User ──< Store ──< PosToken ──< Sale ──< Saledetail
  |         |                    |
  |         ├──< Price           └──< SalePayment
  |         ├──< StoreStock ──< StockMovement
  |         ├──< TableOrder
  |         ├──< HoldOrder
  |         └──< TransferOrder         ← ホスト/クライアントモード
  |
  ├──< Product ──< Price
  |       └──< ProductBundle ──< ProductBundleItem
  |
  ├──< Employee >──< Store
  |
  └──< Provisioning

Sale ──< Refund ──< RefundDetail
PosToken ──< CashLog
```

### 主要テーブル一覧

| テーブル名 | 主要カラム | 用途 |
|-----------|----------|------|
| `users` | `login_name`(unique), `email`(unique), `encrypted_password`, `user_type`, `company_name` | ユーザーアカウント（Devise） |
| `stores` | `name`, `ascii_name`(3-16 英数字, user スコープでユニーク), `user_id` | 店舗情報 |
| `products` | `code`(user スコープでユニーク), `name`, `price`, `status`, `tax_category`, `user_id` | 商品マスタ |
| `product_bundles` | `code`(user スコープでユニーク), `name`, `price`(0=構成品合計), `user_id` | セット商品 |
| `product_bundle_items` | `product_bundle_id`, `product_id`, `quantity` | セット商品の構成 |
| `prices` | `store_id`, `product_id`, `amount` (store+product でユニーク) | 店舗別価格設定 |
| `pos_tokens` | `store_id`, `token`(unique), `name`, `ascii_name`, `password_digest`, `next_receipt_sequence` | POS 端末 |
| `provisioning` | `user_id`, `store_id`, `name`, `store_context`(jsonb), `hardware_settings`(jsonb) | 端末設定 |
| `employees` | `user_id`, `code`(user スコープでユニーク), `name`, `pin_digest`, `is_all_stores`, `failed_attempts`, `locked_at` | 従業員 |
| `employees_stores` | `employee_id`, `store_id` | 従業員-店舗 中間テーブル |
| `sales` | `user_id`, `store_id`, `pos_token_id`, `receipt_number`(unique), `total_amount`, `payment_method` | 売上トランザクション |
| `saledetails` | `sale_id`, `product_id`, `product_name`, `quantity`, `unit_price`, `subtotal`, `tax_rate`, `tax_amount` | 売上明細 |
| `sale_payments` | `sale_id`, `method`, `amount` | 支払い方法（分割払い対応） |
| `refunds` | `user_id`, `store_id`, `sale_id`, `pos_token_id`, `refund_receipt_number`, `total_amount` | 返品トランザクション |
| `refund_details` | `refund_id`, `saledetail_id`, `product_id`, `quantity`, `unit_price`, `subtotal` | 返品明細 |
| `cash_logs` | `pos_token_id`, `employee_id`, `open_date`, `is_start`, `is_end`, `yen_1`〜`yen_10000` | レジ金管理 |
| `store_stocks` | `store_id`, `product_id`, `quantity` (store+product でユニーク) | 店舗別在庫数 |
| `stock_movements` | `store_id`, `product_id`, `store_stock_id`, `quantity_change`, `reason`, `sale_id`, `employee_id` | 在庫変動履歴 |
| `table_orders` | `store_id`, `table_number`(store スコープでユニーク), `items`(jsonb) | 飲食店卓注文 |
| `hold_orders` | `store_id`, `operator_name`, `operator_id`, `total_amount`, `items`(jsonb) | 小売店保留注文 |
| `transfer_orders` | `store_id`, `operator_name`, `operator_id`, `total_amount`, `table_number`(任意), `items`(jsonb) | クライアント→ホスト転送注文 |

### レシート番号フォーマット

**POS 端末発行:**
```
{user.login_name}-{store.ascii_name}-{pos_id}-{seq:08d}
例: yamada-shibuya-3-00000042
```

- `pos_tokens.next_receipt_sequence` を `with_lock`（悲観的ロック）で原子的にインクリメント

**ダッシュボード手動発行:**
```
{user_login_name}-{store_ascii_name}-MANUAL-{YYYYMMDDHHmmss}-{rand4}
例: yamada-shibuya-MANUAL-20260412153045-7823
```

---

## 5. サーバー側 — モデル層

### `User` (`app/models/user.rb`)

Devise によるユーザーアカウント管理。

- **Devise モジュール:** `database_authenticatable`, `registerable`, `recoverable`, `rememberable`, `validatable`, `confirmable`, `lockable`, `trackable`
- **属性:** `login_name`（4-16 英数字、ユニーク）、`first_name`、`last_name`、`company_name`、`user_type`（individual=1, corporate=2）
- **バリデーション:** 利用規約への同意（`terms_of_service`）
- **関連:** `has_many :stores`, `:employees`, `:products`, `:product_bundles`, `:provisionings`, `:sales`

---

### `Store` (`app/models/store.rb`)

店舗情報。

- **属性:** `name`、`ascii_name`（3-16 英数字、user スコープでユニーク）、`address`、`phone_number`、`description`
- **関連:**
  - `belongs_to :user`
  - `has_many :pos_tokens`, `:prices`, `:store_stocks`, `:sales`, `:table_orders`, `:hold_orders`, `:transfer_orders`
  - `has_and_belongs_to_many :employees`
- **コールバック:** 店舗作成時に `is_all_stores=true` の従業員を自動アサイン

---

### `Employee` (`app/models/employee.rb`)

従業員アカウント（PIN 認証）。

- **属性:** `code`（ユニーク/user スコープ, 1-12 文字）、`name`、`pin_digest`、`is_all_stores`、`failed_attempts`（最大 10 回）、`locked_at`
- **PIN 管理:** `has_secure_password :pin`（Bcrypt ハッシュ）、4-6 桁のみ許可
- **アカウントロック:** 10 回失敗で 1 時間ロック
- **メソッド:**
  - `access_locked?` — ロック中かどうか判定
  - `unlock_access!` — ロック解除（失敗カウントリセット）
  - `increment_failed_attempts` — 失敗カウントを増加

---

### `Product` (`app/models/product.rb`)

商品マスタ。

- **属性:** `code`、`name`、`price`、`description`、`status`（active=0, discontinued=1）、`tax_category`（standard=0, reduced=1）
- **税率:** standard=10%、reduced=8%
- **クラスメソッド:** `import(file_path, user)` — CSV ファイルから一括インポート・更新
  - 対応カラム: `code`, `name`, `price`, `description`, `status`, `tax_category`
  - code が既存であれば更新、なければ新規作成

---

### `ProductBundle` / `ProductBundleItem` (`app/models/product_bundle.rb`)

セット商品。

- **ProductBundle:** `code`、`name`、`price`（0 なら構成品の合計価格を使用）
- **ProductBundleItem:** `product_bundle_id`、`product_id`、`quantity`
- 売上登録時に構成商品に展開され、それぞれの在庫が引き落とされる

---

### `Price` (`app/models/price.rb`)

店舗別価格上書き。

- `(store_id, product_id)` の複合ユニーク制約
- レコードなし → `product.price`（デフォルト価格）を使用
- レコードあり → `price.amount` を使用（ダッシュボードで店舗ごとに設定可能）

---

### `PosToken` (`app/models/pos_token.rb`)

POS 端末の認証情報。

- **認証:** `has_secure_token :token`（ランダム生成）、`has_secure_password`（管理者が設定するパスワード）
- **シーケンス:** `next_receipt_sequence` — レシート番号の連番カウンター
- **属性:** `name`、`ascii_name`（レシート番号に使用）、`last_used_at`、`expires_at`
- **関連:** `belongs_to :store`; `has_many :sales`, `:cash_logs`; `belongs_to :provisioning`（任意）

---

### `Provisioning` (`app/models/provisioning.rb`)

端末設定の雛形。

- **`store_context` (JSONB):** `store_id`, `store_name`, `store_mode`（'standard'/'restaurant'/'retail'）、税率設定
- **`hardware_settings` (JSONB):** `receipt_printer_ip`（プリンタ IP アドレス）、`drawer_kick_command`（キャッシュドロア開放コマンド）、`pos_role`（'standard'/'host'/'client'）
- 端末プロビジョニング時に読み込まれ、POS アプリに設定を配布する

---

### `Sale` / `Saledetail` / `SalePayment`

売上トランザクション 3 層構造。

```
Sale（売上ヘッダ）
  ├── receipt_number（ユニーク）
  ├── total_amount
  ├── payment_method（primary: cash/card/barcode）
  └── Saledetail（明細 N 件）
        ├── product_name, quantity, unit_price, subtotal
        └── tax_rate, tax_amount
  └── SalePayment（支払い N 件）
        └── method, amount（分割払い対応）
```

- **注意:** 明細テーブル名は `saledetails`（`sale_details` ではない）

---

### `Refund` / `RefundDetail`

返品トランザクション。

- 1 つの Sale に対して Refund は 1 件のみ
- `refund_receipt_number` = `REFUND-{original_receipt_number}-{timestamp}`
- 返品時は Saledetail で売れた全商品を在庫に戻す（`StockMovement: reason="return"`）

---

### `CashLog` (`app/models/cash_log.rb`)

レジ金の記録。

- **種別の判定:**
  - `is_start=true` → レジ開設
  - `is_start=false, is_end=false` → 中間確認
  - `is_end=true` → 精算（クローズ）
- `total_amount` メソッド: `(yen_10000 * 10000) + (yen_5000 * 5000) + ... + yen_1` で合計算出

---

### `StoreStock` / `StockMovement`

在庫管理。

- `StoreStock`: 店舗×商品の現在在庫数（`quantity`）
- `StockMovement`: 全変動履歴（理由付き）

| `reason` 値 | 意味 |
|------------|------|
| `sale` | 売上による在庫減 |
| `return` | 返品による在庫増 |
| `manual_in` | 手動入庫 |
| `manual_out` | 手動出庫 |
| `transfer_in` | 店舗間移動（受け入れ） |
| `transfer_out` | 店舗間移動（払い出し） |
| `manual_adjustment` | ダッシュボードからの直接修正 |

---

### `TableOrder` / `HoldOrder` / `TransferOrder`

同一店舗内の複数 POS 間で共有されるトランジット注文データ。いずれも `store_id` でスコープされ、店舗をまたいでデータが漏れない。

- **`TableOrder`:** 飲食店モード。卓番ごとに注文中アイテムを JSONB で保持。`table_number` は store スコープでユニーク
- **`HoldOrder`:** 小売店モード。保留注文（番号・担当者・アイテム・合計金額）を保持
- **`TransferOrder`:** ホスト/クライアントモード。クライアント機がスキャンした商品をホスト機に転送するための中間バッファ。受け取り（DELETE）と同時に削除される使い捨てレコード

---

## 6. サーバー側 — API コントローラー

全 API は `/api/v1/` 以下。`login` を除くすべてのアクションで Bearer トークン認証が必要。

```http
Authorization: Bearer <pos_token>
# または
X-POS-Token: <pos_token>
```

---

### `Api::V1::PosDevicesController`

**`POST /api/v1/pos_devices/login`** — 端末ログイン（認証不要）

```
Request:
  pos[userName]    # ユーザーの login_name
  pos[storeName]   # 店舗の ascii_name
  pos[posName]     # POS 端末の ascii_name
  pos[password]    # POS 端末のパスワード

Response:
  { success, token, pos_id, user_login_name, store_ascii_name, next_receipt_sequence }
```

処理: 認証成功後にトークンを再生成（旧トークン無効化）、パスワードを nil に設定。

---

**`POST /api/v1/pos_devices/top_user_login`** — 従業員ログイン（PIN 認証）

```
Request: { code, pin }
Response: { success, employee_id, employee_name } または エラー
```

処理フロー:
1. `code` で従業員を検索
2. アカウントロック確認（`locked_at` + 1 時間以内）
3. `pin` の Bcrypt 比較
4. 失敗: `failed_attempts` インクリメント、10 回で `locked_at` セット
5. 成功: `failed_attempts` リセット、店舗アクセス権限確認

---

**`POST /api/v1/pos_devices/verify_employee`** — 中間操作の従業員認証

`top_user_login` と同じロジック。返品・在庫操作など権限が必要な中間操作に使用。

---

**`POST /api/v1/pos_devices/check_operator`** — 担当者名前確認（PIN 不要）

```
Request: { code }
Response: { success, name, employee_id }
```

---

**`GET /api/v1/pos_devices/provisioning`** — 端末設定取得

```
Response: { success, provisioning: { store_context, hardware_settings } }
```

優先順位: POS トークンに紐付いたプロビジョニング → 店舗の最新プロビジョニング

---

**`POST /api/v1/pos_devices/open`** — レジ開設

```
Request: { employee_id, open_date, cash_drawer: { yen_1, yen_5, ... }, total_amount }
Response: { success }
```

`CashLog` を `is_start=true` で作成。総額はサーバー側で再計算して検証。

---

**`GET /api/v1/pos_devices/cash_check_context`** — レジ金確認の基準値取得

```
Response: { success, last_amount, expected_amount, last_logged_at }
```

`expected_amount` の計算:
```
レジ開設時の金額
  + 開設後の現金売上合計 (sale_payments.method = cash)
  - 開設後の現金返金合計 (pro-rata 按分)
```

---

**`POST /api/v1/pos_devices/cash_check`** — 中間レジ金確認

```
Request: { employee_id, cash_drawer: {...}, total_amount }
Response: { success, last_amount, expected_amount, actual_amount, diff_amount, last_logged_at }
```

`CashLog` を `is_start=false, is_end=false` で作成。

---

**`POST /api/v1/pos_devices/close_register`** — レジ精算

同上。`CashLog` を `is_end=true` で作成。

---

### `Api::V1::SalesController`

**`POST /api/v1/sales`** — 売上登録

```
Request:
{
  sale: {
    total_amount,
    payment_method,   # 0=cash, 1=card, 2=barcode
    subtotal_ex_tax,
    tax_amount,
    receipt_number    # オプション（省略時はサーバー生成）
  },
  details: [
    {
      product_id?,
      product_code?,
      product_name?,
      quantity,
      unit_price,
      subtotal?,
      tax_rate?,
      tax_amount?,
      bundle_code?    # セット商品の場合
    }
  ],
  payments: [{ method, amount }],  # 分割払い対応
  employee_id?
}

Response: { success, sale_id, receipt_number, next_receipt_sequence }
```

**トランザクション内処理:**
1. `Sale` レコード作成（`receipt_number` 自動生成時は `pos_token.with_lock` で原子的インクリメント）
2. 各 `detail` について:
   - `bundle_code` あり → `ProductBundle` を展開し構成商品ごとに `Saledetail` 作成
   - 通常商品 → `Saledetail` 作成
   - 各商品の `StoreStock` を `with_lock` で在庫引き落とし + `StockMovement` 記録
3. 各 `payment` について `SalePayment` 作成

---

### `Api::V1::ProductsController`

**`POST /api/v1/products/sync`** — 商品マスタ同期（カーソルページネーション）

```
Request: { last_updated_at?, last_id? }  # 続きから取得する場合

Response:
{
  success: true,
  server_time,         # クライアント時刻補正用
  has_more: bool,
  last_updated_at,
  last_id,
  products: [
    { id, code, name, description, status, price, tax_category, updated_at }
    # price は店舗別価格設定があればそれを返す
  ],
  bundles: [
    { id, code, name, price, items: [{ product_id, product_code, quantity }] }
  ]
}
```

1 バッチ 1000 件。`has_more=true` の間、クライアントは `last_updated_at` / `last_id` を送り続けて全件取得。

---

### `Api::V1::RefundsController`

**`GET /api/v1/refunds/sale_by_receipt`** — レシート番号で売上検索

```
Query: ?receipt_number=...
Response: { success, sale: {...}, details: [...], payments: [...] }
```

---

**`POST /api/v1/refunds`** — 返品処理

```
Request:
{
  receipt_number,
  employee_ids: [id1, id2],  # 2名以上の承認が必要
  details: [{ saledetail_id, quantity }]
}

Response: { success, refund_id, refund_receipt_number, total_refund_amount }
```

**バリデーション:**
- `employee_ids` が 2 件以上、かつ全員が PIN 認証済みで店舗アクセス権限あり
- 返品数量 ≦ 元売上数量
- 同一 Sale に対して 2 度の返品は不可

---

### `Api::V1::StoreStocksController`

**`POST /api/v1/store_stocks/move`** — 在庫移動（入出庫）

```
Request:
{
  employee_id,
  movements: [
    { jan_code, quantity, direction: "in" | "out" }
  ]
}

Response:
{
  success,
  movements: [
    { jan_code, product_name, direction, quantity, stock_quantity }
  ]
}
```

各商品を `with_lock` して原子的に在庫増減。`StockMovement.reason` = `"manual_in"` または `"manual_out"`。

---

### `Api::V1::TableOrdersController`

飲食店モード：卓注文の共有（同一店舗の複数 POS 間）。

| メソッド | パス | 説明 |
|---------|------|------|
| GET | `/api/v1/table_orders` | 注文中の全卓番一覧 |
| GET | `/api/v1/table_orders/:table_number` | 指定卓のアイテム取得 |
| PUT | `/api/v1/table_orders/:table_number` | アイテム保存（upsert） |
| DELETE | `/api/v1/table_orders/:table_number` | 卓注文削除（会計完了時） |

---

### `Api::V1::HoldOrdersController`

小売店モード：保留注文の共有（同一店舗の複数 POS 間）。

| メソッド | パス | 説明 |
|---------|------|------|
| GET | `/api/v1/hold_orders` | 全保留一覧（アイテムなし） |
| POST | `/api/v1/hold_orders` | 新規保留作成 → `hold_number`（id）返却 |
| DELETE | `/api/v1/hold_orders/:id` | 保留呼び出し（全データ返却 + 削除） |

---

### `Api::V1::TransferOrdersController`

ホスト/クライアントモード：クライアント機からホスト機へのカート転送。

| メソッド | パス | 説明 |
|---------|------|------|
| GET | `/api/v1/transfer_orders` | 未処理の転送注文一覧（アイテムなし、ホスト待ち受け用） |
| POST | `/api/v1/transfer_orders` | クライアント機がカートを転送 → `id` 返却 |
| DELETE | `/api/v1/transfer_orders/:id` | ホスト機が受け取り（全データ返却 + 同時削除） |

**POST リクエスト形式:**
```json
{
  "transfer_order": {
    "operator_name": "山田",
    "operator_id": 5,
    "total_amount": 1200,
    "table_number": null,
    "items": [ { "product": {...}, "quantity": 2, "bundle_code": null } ]
  }
}
```

**DELETE レスポンス形式:**
```json
{
  "success": true,
  "transfer_order": {
    "id": 42,
    "operator_name": "山田",
    "operator_id": 5,
    "total_amount": 1200,
    "table_number": null,
    "items": [...]
  }
}
```

- `items` の各エントリは `ScannedItem.toJson()` 形式（`product` オブジェクト + `quantity` + `bundle_code` 等）
- DELETE で受け取るとレコードが削除される。同じ転送を 2 度受け取ることは不可能（404 を返す）

---

## 7. サーバー側 — ダッシュボード コントローラー

ブラウザから Devise セッション認証でアクセス。全操作は `current_user` にスコープされる。

### `Dashboard::DashboardsController`

- **`index`**: 店舗一覧と POS トークン一覧を表示するホーム画面

### `Dashboard::ProductsController`

- **`index`**: 商品一覧（コード・名前検索、ステータスフィルタ、50件/ページ）
- **CRUD**: `new`, `create`, `edit`, `update`, `destroy`
- **`import` (POST)**: CSV アップロード → `ProductImportJob`（非同期バックグラウンド処理）
  - 対応カラム: `code`, `name`, `price`, `description`, `status`, `tax_category`
  - 二重インポート防止のロック機構（30 分タイムアウト）

### `Dashboard::StoresController`

- **CRUD**: `index`, `new`, `create`, `edit`, `update`, `destroy`
- **`prices` (GET)**: 商品一覧 + 店舗別価格上書き表示
- **`update_prices` (PATCH)**: 店舗別価格の一括更新
  - 空または標準価格と同じ場合: `Price` レコードを削除（標準に戻す）
  - 異なる場合: `Price` レコードを保存・更新
  - N+1 対策: `products_by_id = current_user.products.where(id: product_ids).index_by { |p| p.id.to_s }` で一括プリロード

### `Dashboard::EmployeesController`

- **CRUD**: `index`, `new`, `create`, `edit`, `update`, `destroy`
- `is_all_stores=1` に設定した場合、全店舗に自動割り当て
- PIN が空白の場合は `nil` セット（PIN なしの従業員も許容）

### `Dashboard::SalesController`

- **`index`**: 売上一覧（店舗・日付範囲フィルタ、50件/ページ）
- **CSV エクスポート**: `sales_#{Date.current}.csv`（支払い方法内訳付き）

### `Dashboard::RefundsController`

- **`index`**: 返品一覧（フィルタ・ページネーション）
- **`show`**: 返品詳細表示

### `Dashboard::ReportsController`

- **`index`**: 売上分析
  - 日別集計（件数・金額）
  - 月別集計（件数・金額）
  - 上位 20 商品（売上金額順）
  - CSV エクスポート

### `Dashboard::StoreStocksController`

- **`index`**: JAN コードで商品検索 → 店舗別在庫数表示
- **`update`**: 在庫数直接編集（差分を `StockMovement` に記録、`with_lock` で排他制御）
- **`transfer` (POST)**: 店舗間在庫移動
  - 同一店舗への移動はエラー
  - トランザクション: `from_stock.with_lock` で在庫不足確認 → 引き落とし → `to_stock.with_lock` で追加

### `Dashboard::ProductBundlesController`

- セット商品の CRUD
- `items[n][product_id]` / `items[n][quantity]` の配列形式フォームを処理

### `Dashboard::ProvisioningsController`

- **`new`, `create`**: プロビジョニング設定の作成
  - `store_context` に `store_mode`（'standard'/'restaurant'/'retail'）を格納
  - `hardware_settings` にデフォルトのキャッシュドロア開放コマンド（`27,112,0,50,250`）と `pos_role`（'standard'/'host'/'client'）を格納
  - フォームに店舗モードと POS ロールの両方を選択する UI を提供
- **`destroy`**: プロビジョニング削除

### `Dashboard::PosDevicesController`

- **`new`, `create`**: POS 端末の新規登録
  - パスワードはランダム 6 桁自動生成（表示は一度限り）
- **`update_password`**: パスワードリセット、トークン再生成

### `Dashboard::CashLogsController`

- **`index`**: レジ開設・確認・精算ログ一覧（店舗・POS・日付・種別フィルタ）

### `Dashboard::StockMovementsController`

- **`index`**: 在庫変動履歴（商品・売上・従業員・POS 情報付き）

---

## 8. サーバー側 — ルーティング

**`Server/onlipos/config/routes.rb`**

```
# Devise 認証
devise_for :users  →  /users/sign_in, /users/sign_up, etc.

# 静的ページ
root to: 'pages#top'
get '/terms' → pages#terms

# ダッシュボード（セッション認証）
namespace :dashboard do
  root to: 'dashboards#index'
  resources :pos_devices      new, create, update_password
  resources :stores           + :prices, :update_prices
  resources :employees        CRUD
  resources :products         + :import
  resources :provisionings    index, new, create, destroy
  resources :sales            + CSV エクスポート
  resources :sale_details     show のみ
  resources :cash_logs        index のみ
  resources :store_stocks     index, update + :transfer
  resources :stock_movements  index のみ
  resources :product_bundles  CRUD
  resources :reports          index + CSV エクスポート
end

# POS API（Bearer トークン認証）
namespace :api do
  namespace :v1 do
    # POS デバイス操作
    post   'pos_devices/login'
    post   'pos_devices/top_user_login'
    post   'pos_devices/verify_employee'
    post   'pos_devices/check_operator'
    post   'pos_devices/provisioning'
    post   'pos_devices/open'
    post   'pos_devices/cash_check'
    post   'pos_devices/close_register'
    get    'pos_devices/cash_check_context'

    # 商品同期
    post 'products/sync'

    # 売上
    resources :sales,  only: [:create]

    # 返品
    resources :refunds, only: [:create] do
      collection { get :sale_by_receipt }
    end

    # 在庫移動
    post 'store_stocks/move'

    # 飲食店モード：卓注文
    resources :table_orders, only: [:index] do
      collection do
        get    ':table_number' → show
        put    ':table_number' → upsert
        delete ':table_number' → destroy
      end
    end

    # 小売店モード：保留注文
    resources :hold_orders, only: [:index, :create, :destroy]

    # ホスト/クライアントモード：カート転送注文
    resources :transfer_orders, only: [:index, :create, :destroy]
  end
end
```

---

## 9. サーバー側 — バックグラウンドジョブ

### `ProductImportJob` (`app/jobs/product_import_job.rb`)

**目的:** CSV ファイルからの商品一括インポートを非同期処理する。

**処理フロー:**
1. ダッシュボードで CSV ファイルをアップロード
2. `ProductsController#import` がファイルを一時保存し、`ProductImportJob.perform_later` をエンキュー
3. Solid Queue ワーカーがジョブを拾い上げる
4. `Product.import(file_path, user)` を呼び出し（各行を upsert）
5. 処理完了後: 一時ファイル削除 + ロック解除

**二重インポート防止:**
`products_import_lock` キャッシュキーで 30 分間のロックを取得。同時に複数インポートが走ることを防ぐ。

---

## 10. クライアント側 — アプリ起動フロー

```
アプリ起動
     │
     ▼
main.dart
  ├─ デスクトップ: sqflite_common_ffi 初期化
  ├─ デスクトップ: window_manager でフルスクリーン・キオスクモード設定
  └─ FlutterSecureStorage から 'LoginToken' 読み取り
        │
        ├─ トークンなし → SetupPage（初回プロビジョニング）
        │     │
        │     ▼
        │  サーバー URL・ユーザー名・店舗名・POS 名・パスワード入力
        │  POST /api/v1/pos_devices/login
        │  → トークン保存 → ProvisioningPage
        │
        └─ トークンあり → LoginTopView（毎日の通常ログイン）
              │
              ▼
           日付選択 + 従業員コード + PIN 入力
           POST /api/v1/pos_devices/top_user_login
              │
              ▼
           OpenView（レジ開設 - 金種入力）
           POST /api/v1/pos_devices/open
              │
              ▼
           MenuTopView（メインメニュー）
```

---

## 11. クライアント側 — 機能別モジュール

### `lib/setup/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `setup_view.dart` | `SetupPage` | 初回プロビジョニング UI |
| `setup_api.dart` | `Setup_Api` | `POST /api/v1/pos_devices/login` の呼び出し |

**`Setup_Api` が保存するデータ:**

```
FlutterSecureStorage:
  LoginToken         → Bearer トークン
  AccessUrl          → サーバー URL
  ReceiptPosId       → POS 端末 ID
  NextReceiptSequence → 次のレシート連番
  ReceiptUserLoginName → ユーザー名（レシート番号用）
  ReceiptStoreAsciiName → 店舗名（レシート番号用）
```

---

### `lib/login/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `login_top_view.dart` | `LoginTopView` | 日付選択・従業員コード・PIN 入力画面 |
| `login_api.dart` | `LoginApi` | 従業員ログイン・検証 API |
| `operator_input_view.dart` | `OperatorInputView` | 担当者選択画面（中間操作時） |

**`OperatorInputView` の分岐ロジック:**
```
担当者認証成功
    │
    ├─ storeMode == 'restaurant' かつ リスト表示でない
    │     → TableNumberInputView（卓番入力）
    │
    └─ それ以外
          ├─ isListMode == true → SaleListView
          └─ isListMode == false → SaleScanView(storeMode: storeMode)
```

---

### `lib/startup/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `open_view.dart` | `OpenView` | レジ開設（金種入力） |
| `open_api.dart` | `OpenApi` | `POST /api/v1/pos_devices/open` の呼び出し |

---

### `lib/provisioning/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `provisioning_view.dart` | `ProvisioningPage` | 端末設定の取得・商品同期・オフライン送信 |
| `provisioning_api.dart` | `ProvisioningApi` | `GET /api/v1/pos_devices/provisioning` |

**`ProvisioningPage` の処理:**
1. `GET /api/v1/pos_devices/provisioning` → `hardware_settings`・`store_context` 取得
2. `PrinterIP`・`StoreName`・`StoreMode`・**`PosRole`** 等を `FlutterSecureStorage` に保存
3. `ProductSyncService.syncProducts()` → SQLite に商品マスタを全件ダウンロード（カーソルページネーション）
4. `SentToApi().drainOfflineQueue()` → オフラインキューの再送信

---

### `lib/menu/`

| ファイル | 役割 |
|---------|------|
| `menu_top_view.dart` | メインメニュー画面（StatefulWidget。`PosRole` を読み取りホスト機のみ「待ち受けモード」タイルを追加表示） |
| `menu_top_controller.dart` | メニューナビゲーションの状態管理 |

---

### `lib/sale/`

売上登録の中核モジュール。

| ファイル | クラス | 役割 |
|---------|-------|------|
| `sale_scan_view.dart` | `SaleScanView` | スキャン型売上入力画面（バーコード） |
| `sale_list_view.dart` | `SaleListView` | 一覧型売上入力画面（タッチ操作） |
| `sale_item.dart` | `ScannedItem` | 売上明細アイテムのデータクラス |
| `payment_view.dart` | `PaymentView` | 支払い入力・会計処理 |
| `send_to_api.dart` | `SentToApi` | 売上 API 送信・オフラインキュー管理 |
| `offline_sale_repository.dart` | `OfflineSaleRepository` | SQLite オフラインキュー操作 |
| `table_number_input_view.dart` | `TableNumberInputView` | 飲食店モード：卓番入力画面 |
| `table_order_api.dart` | `TableOrderApi` | 卓注文 API クライアント |
| `table_order_store.dart` | `TableOrderStore` | 卓注文インメモリ（オフラインフォールバック） |
| `hold_order_api.dart` | `HoldOrderApi` | 保留注文 API クライアント |
| `hold_order_store.dart` | `HoldOrderStore` | 保留注文インメモリ（オフラインフォールバック） |
| `transfer_order_api.dart` | `TransferOrderApi`, `TransferOrderEntry`, `ClaimedTransferOrder` | ホスト/クライアントモード転送注文 API クライアント |
| `host_waiting_view.dart` | `HostWaitingView` | ホスト機待ち受け画面（5秒自動更新・ダーク Metro UI） |

**`ScannedItem` クラス:**

```dart
class ScannedItem {
  final Product product;
  final String? bundleCode;  // セット商品から展開された場合のセットコード
  final String? bundleName;
  int quantity;

  int get subtotal => product.price * quantity;

  int get taxAmount {
    // 税込価格から消費税額を逆算
    final exTax = (subtotal * 100 / (100 + product.taxRate)).floor();
    return subtotal - exTax;
  }
}
```

**`SaleScanView` のパラメータ:**

| パラメータ | 型 | 説明 |
|----------|---|------|
| `operatorName` | `String` | 担当者名 |
| `operatorId` | `int` | 担当者 ID |
| `storeMode` | `String` | `'standard'`/`'restaurant'`/`'retail'` |
| `tableNumber` | `String?` | 飲食店モード時の卓番 |
| `initialItems` | `List<ScannedItem>?` | ホストがクライアントから受け取った転送注文のプリロード商品 |

**`SaleScanView` の `storeMode` / `posRole` による動作の違い:**

```
storeMode: standard（標準）
  → 通常の売上スキャン・会計

storeMode: restaurant（飲食店）
  → 起動時: GET /api/v1/table_orders/:table_number で既存注文復元
  → スキャン後: PUT /api/v1/table_orders/:table_number（fire-and-forget）
  → 全クリア時: DELETE /api/v1/table_orders/:table_number
  → AppBar に「卓 X 担当: Y」表示

storeMode: retail（小売店）
  → 「保留・呼び出し」ボタン表示
  → カートにアイテムあり: 保留作成 → 保留票印刷
  → カートが空: 保留一覧 → 番号入力 → 注文復元

posRole: client（クライアント機）—storeMode と独立して動作—
  → 「転送」ボタン（青い FAB）追加
  → 転送実行: POST /api/v1/transfer_orders → カートクリア
  → 転送 ID をスナックバーで表示

posRole: host（ホスト機）—storeMode と独立して動作—
  → initialItems があれば起動時にカートにプリロード
  → MenuTopView に「待ち受けモード」タイル表示
```

---

### `lib/refund/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `return_refund_view.dart` | `ReturnRefundView` | 返品処理メイン画面 |
| `refund_api.dart` | `RefundApi` | 返品 API クライアント |
| `qr_scan_receipt_view.dart` | `QrScanReceiptView` | レシート QR スキャン |

---

### `lib/cash/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `cash_check_view.dart` | `CashCheckView` | 中間レジ金確認画面 |
| `cash_close_view.dart` | `CashCloseView` | レジ精算（EOD）画面 |
| `cash_log_api.dart` | `CashLogApi` | レジ金 API クライアント |

---

### `lib/inventory/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `inventory_inout_view.dart` | `InventoryInoutView` | 在庫入出庫画面 |
| `inventory_api.dart` | `InventoryApi` | `POST /api/v1/store_stocks/move` |

---

### `lib/product/`

| ファイル | クラス | 役割 |
|---------|-------|------|
| `product.dart` | `Product`, `ProductBundle`, `BundleItem` | 商品データクラス |
| `product_repository.dart` | `ProductRepository` | SQLite 商品データ読み取り |
| `database_service.dart` | `DatabaseService` | SQLite シングルトン接続 |
| `master_sync_api.dart` | `ProductSyncService` | 商品マスタ同期（API → SQLite） |

---

### `lib/settings/`

| ファイル | 役割 |
|---------|------|
| `settings_view.dart` | アプリ設定表示（サーバー URL・店舗モード・税率など） |

---

## 12. クライアント側 — ローカルデータ管理

### SQLite データベース（`DatabaseService`）

**シングルトンパターン:** `DatabaseService.instance.database` で全クラスが同一接続を共有（"database is locked" 防止）。

**スキーマバージョン: 3**

```sql
-- 商品マスタ（サーバーから同期）
CREATE TABLE products (
  id INTEGER PRIMARY KEY,
  code TEXT,
  name TEXT,
  description TEXT,
  price INTEGER,
  tax_category INTEGER DEFAULT 0,
  status TEXT,
  updated_at TEXT
);

-- セット商品
CREATE TABLE product_bundles (
  id INTEGER PRIMARY KEY,
  code TEXT UNIQUE,
  name TEXT,
  price INTEGER DEFAULT 0
);

-- セット商品構成
CREATE TABLE product_bundle_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  product_bundle_id INTEGER,
  product_id INTEGER,
  product_code TEXT,
  quantity INTEGER DEFAULT 1
);

-- オフライン売上キュー（ネットワーク復旧後に再送信）
CREATE TABLE offline_sales_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  receipt_number TEXT,
  payload TEXT,      -- JSON 文字列
  created_at TEXT
);
```

### `FlutterSecureStorage` キー一覧

| キー | 内容 |
|-----|------|
| `LoginToken` | POS Bearer トークン |
| `AccessUrl` | サーバー URL |
| `ReceiptPosId` | POS 端末 ID |
| `NextReceiptSequence` | 次のレシート連番 |
| `ReceiptUserLoginName` | ユーザー名（レシート番号用） |
| `ReceiptStoreAsciiName` | 店舗名（レシート番号用） |
| `PrinterIP` | レシートプリンタ IP アドレス |
| `StoreName` | 店舗名（レシート印刷用） |
| `DrawerKickCommand` | キャッシュドロア開放コマンド |
| `StoreMode` | 店舗モード（'standard'/'restaurant'/'retail'） |
| `PosRole` | POS ロール（'standard'/'host'/'client'） |

---

## 13. クライアント側 — ESC/POS レシート印刷

**`lib/sale/escpos/lan_recipt_api.dart`**

LAN 接続のサーマルプリンタ（TCP ポート 9100）に ESC/POS コマンドを直接送信する。

### `ReceiptPrinter.printReceipt()`

```
┌─────────────────────────────┐
│  [店舗名 - 大文字・中央]     │
│         領 収 書             │
│  ────────────────────────   │
│  日時: 2026-04-12 15:30:00  │
│  No: yamada-shop-1-00000042 │
│  [extraInfo: 卓 3 など]      │
│  ────────────────────────   │
│  4902778012345  商品名       │
│        1 x 1200 = 1200      │
│  ────────────────────────   │
│  税抜小計 ¥1090              │
│  消費税   ¥110               │
│  合計   ¥1200  [大字]        │
│  現金: 1000 / カード: 200    │
│  お預かり: 1500              │
│  お釣り: 300  [大字]         │
│  ────────────────────────   │
│  ご利用ありがとうございます  │
│                              │
│  [QR コード - レシート番号]  │
│  yamada-shop-1-00000042      │
└─────────────────────────────┘
```

**文字エンコード:** `charset_converter` で Shift_JIS に変換（ESC/POS プリンタの日本語対応）。

**`printHoldSlip()`** — 小売店モード保留票

```
┌─────────────────────────────┐
│        [店舗名]              │
│      ** 保  留  票 **        │
│  ────────────────────────   │
│  日時: 2026-04-12 15:30:00  │
│  担当: 山田太郎              │
│  ────────────────────────   │
│        保 留 番 号           │
│             5  [超大字]      │
│  ────────────────────────   │
│  商品名                     │
│       2個 x ¥1200 = ¥2400   │
│  ────────────────────────   │
│  合計  ¥2400  [大字]         │
│  この票を係員にお渡しください │
└─────────────────────────────┘
```

**`openDrawer()`** — キャッシュドロア開放

- `DrawerKickCommand` から ESC/POS コマンドバイト列を読み取り送信
- デフォルトコマンド: `27,112,0,50,250`（ESC p 0 50 250）

---

## 14. 認証・セキュリティ設計

### 多層認証アーキテクチャ

```
レイヤー 1: POS 端末認証
  PosToken.token（ランダム生成 SecureRandom）
  → 全 API リクエストの Authorization: Bearer ヘッダー

レイヤー 2: 従業員 PIN 認証
  Employee.pin（Bcrypt ハッシュ）
  → 売上ログイン・返品承認・在庫操作

レイヤー 3: ダッシュボード認証
  User.encrypted_password（Devise + Bcrypt）
  → ブラウザセッション
```

### アカウントロック（従業員 PIN）

```
失敗 1-9 回: failed_attempts インクリメント
失敗 10 回: locked_at = Time.current → 1 時間ロック
ロック中:   access_locked? = true → API が 423 相当を返す
ロック解除: unlock_access! → failed_attempts = 0, locked_at = nil
```

### 返品の二重承認

```dart
// ReturnRefundView で 2 名の従業員 PIN を収集
employee_ids: [employee1_id, employee2_id]
// サーバー側で全員の認証・権限確認
```

### マルチテナント データ分離

```ruby
# 全クエリが current_user スコープ
@stores = current_user.stores
@products = current_user.products
# 他のユーザーのデータには絶対にアクセスできない
```

### レシート番号の重複防止

```ruby
# 悲観的ロックで原子的にインクリメント
pos_token.with_lock do
  seq = pos_token.next_receipt_sequence
  pos_token.increment!(:next_receipt_sequence)
  "#{user_login}-#{store_ascii}-#{pos_id}-#{seq.to_s.rjust(8, '0')}"
end
```

---

## 15. オフライン対応設計

POS 端末はネットワーク障害時でも売上登録を継続できる。

### 通常フロー

```
SaleScanView → PaymentView → SentToApi.sendSale()
    │
    ├─ 成功 (201) → receipt_number 返却、レシート印刷
    └─ SocketException / TimeoutException
          │
          ▼
       _saveOffline()
          ├─ ローカル連番でレシート番号生成
          │    (NextReceiptSequence キーから採番)
          └─ SQLite offline_sales_queue にエンキュー
               → 成功として扱い、レシート印刷も行う
```

### 再送信フロー

```
ProvisioningPage 起動時
または オンライン売上成功時（バックグラウンド）
    │
    ▼
drainOfflineQueue()
    │
    └─ pending 件を順番に POST /api/v1/sales
         ├─ 成功 (201): キューから削除
         ├─ 409 Conflict (重複): キューから削除（サーバーに既存）
         ├─ 401/403: キューに残す（トークン切れ → 再認証後に再送）
         └─ 5xx: キューに残す（サーバーエラー → 次回再試行）
         SocketException/TimeoutException: 処理中断、次回に持ち越し
```

### オフライン連番とサーバー連番の同期

- オフライン中はローカルの `NextReceiptSequence` から採番し +1 ずつインクリメント
- オンライン売上が成功すると、サーバーレスポンスの `next_receipt_sequence` で上書き（サーバーの連番を正とする）

---

## 16. 店舗モード（飲食店 / 小売店 / 標準）

### モード設定フロー

```
ダッシュボード: Provisioning 作成時に store_mode を選択
    ↓
store_context JSONB に格納
    ↓
端末プロビジョニング時: GET /api/v1/pos_devices/provisioning
    ↓
FlutterSecureStorage['StoreMode'] に保存
    ↓
OperatorInputView で読み取り → 画面遷移を分岐
```

### 飲食店モード（restaurant）

```
担当者ログイン
    ↓
TableNumberInputView（卓番入力）
    ├─ GET /api/v1/table_orders → 注文中テーブルをオレンジボタンで表示
    └─ 卓番確定 → SaleScanView(storeMode: 'restaurant', tableNumber: '3')
          │
          ├─ 起動時: GET /api/v1/table_orders/3 → 既存注文を復元
          ├─ スキャン毎: PUT /api/v1/table_orders/3（fire-and-forget）
          └─ 会計後: DELETE /api/v1/table_orders/3
```

- 同一店舗の複数 POS が同じ卓の注文を共有
- API 失敗時は `TableOrderStore`（インメモリ）にフォールバック

### 小売店モード（retail）

```
SaleScanView に「保留・呼び出し」ボタン追加
    │
    ├─ カートにアイテムあり → 保留作成
    │     POST /api/v1/hold_orders → hold_number 取得
    │     ReceiptPrinter.printHoldSlip() → 保留票印刷
    │     カートクリア
    │
    └─ カートが空 → 保留呼び出し
          GET /api/v1/hold_orders → 保留一覧表示
          番号入力 → DELETE /api/v1/hold_orders/:id → アイテム復元
```

- 保留番号はサーバーが採番（`HoldOrder.id`）
- 同一店舗内の全 POS から呼び出し可能

### 標準モード（standard）

- 上記の卓番・保留機能なし
- 通常の売上スキャン

---

## 17. ホスト・クライアント型 POS モード

### 概念

1 つの店舗内の POS 端末をロール（役割）で区別する。

| ロール | 用途 | 追加機能 |
|--------|------|---------|
| `standard` | 従来通り。スキャン〜会計を単独完結 | なし |
| `client` | フロア持ち歩きタブレット。商品スキャンに特化 | 「転送」ボタン |
| `host` | レジカウンター専用機。会計処理に特化 | 「待ち受けモード」タイル |

`storeMode`（飲食店/小売店/標準）と `posRole`（ホスト/クライアント/標準）は**独立して設定可能**。例えば「飲食店モード + クライアント機」という構成も可能。

### 設定フロー

```
ダッシュボード: Provisioning 作成時に pos_role を選択
    ↓
hardware_settings JSONB に pos_role: 'host' または 'client' として格納
    ↓
端末プロビジョニング時: GET /api/v1/pos_devices/provisioning
    ↓
FlutterSecureStorage['PosRole'] に保存
    ↓
MenuTopView・SaleScanView で読み取り → UI を分岐
```

### クライアント機のフロー

```
クライアント機 (PosRole: 'client')
    │
    ▼
SaleScanView（通常通り商品をスキャン）
    │
    ├─ 「転送」ボタン（青い FAB）をタップ
    │     ↓
    │   確認ダイアログ
    │     ↓
    │   POST /api/v1/transfer_orders
    │   { operator_name, operator_id, total_amount, table_number?, items[] }
    │     ↓
    │   サーバーが TransferOrder レコードを作成 → id を返却
    │     ↓
    │   スナックバーに「転送しました（転送ID: 42）」表示
    │   カートクリア → 次の客対応へ
    │
    └─ 「小計」ボタンで自端末会計も可能（通常通り）
```

### ホスト機のフロー

```
ホスト機 (PosRole: 'host')
    │
    ▼
MenuTopView に「待ち受けモード」タイル表示
    │
    ▼
HostWaitingView（5秒ごとに自動更新）
    │
    ▼
GET /api/v1/transfer_orders
→ 転送一覧 [{ id, operator_name, total_amount, item_count, created_at }, ...]
    │
    ▼
転送カードの「受け取る」ボタンをタップ
    │
    ▼
確認ダイアログ（担当者・点数・金額を表示）
    │
    ▼
DELETE /api/v1/transfer_orders/:id
→ { success, transfer_order: { items[], operator_name, total_amount, ... } }
→ サーバーのレコード削除（同一転送を 2 度受け取れない）
    │
    ▼
SaleScanView(initialItems: claimed.items) に遷移
カートに転送内容がプリロードされた状態で会計処理へ
```

### `transfer_orders` テーブルの役割

```
TransferOrder は「使い捨て中間バッファ」として機能する。

クライアント機がカートを確定
  → TransferOrder 作成（store_id でスコープ）
      ↓
ホスト機が受け取る
  → TransferOrder 削除（同時に items を返却）

待ち受けリストに残るのは「未処理の転送のみ」
古い転送（ネットワーク障害等で受け取られなかった）は
アプリ上で一覧に残り続ける。必要に応じて手動削除や
TTL によるサーバー側クリーンアップが推奨される。
```

---

## 18. データフロー — 売上登録

```
[Flutter クライアント]

スキャン/選択
    │
    ▼
ScannedItem リスト構築
  - product.id, product.code, product.name, product.price
  - bundleCode/bundleName（セット商品の場合）
  - quantity

    │
    ▼
PaymentView
  - 支払い方法・金額入力
  - 合計・税額・おつり計算

    │
    ▼
SentToApi.sendSale()
  ┌─ オンライン → POST /api/v1/sales
  └─ オフライン → SQLite キューに保存

[Rails サーバー]

POST /api/v1/sales
    │
    ▼
Transaction:
  1. Sale 作成
     ├─ receipt_number: pos_token.with_lock でシーケンス採番
     └─ total_amount, payment_method, subtotal_ex_tax, tax_amount

  2. 各 detail について:
     ├─ bundle_code あり:
     │   ProductBundle 取得 → 構成商品に展開
     │   各構成商品の Saledetail 作成
     └─ 通常商品:
         Saledetail 作成（product_name, qty, unit_price, subtotal, tax_rate, tax_amount）

  3. 各商品の在庫更新:
     StoreStock.find_or_create_by(store, product).with_lock do
       decrement! quantity
       StockMovement.create!(reason: "sale")
     end

  4. 各 payment について SalePayment 作成

    │
    ▼
Response: { success, sale_id, receipt_number, next_receipt_sequence }

[Flutter クライアント]

  ReceiptPrinter.printReceipt() → TCP 9100 でプリンタへ ESC/POS 送信
  NextReceiptSequence 更新（サーバー値で上書き）
```

---

## 19. データフロー — 返品処理

```
[Flutter クライアント]

ReturnRefundView:
  1. レシート番号入力（または QR スキャン）
  2. GET /api/v1/refunds/sale_by_receipt?receipt_number=...
     → 元売上の明細表示

  3. 返品数量選択

  4. 第 1 従業員 PIN 入力
     POST /api/v1/pos_devices/verify_employee → employee_id_1

  5. 第 2 従業員 PIN 入力
     POST /api/v1/pos_devices/verify_employee → employee_id_2

  6. POST /api/v1/refunds
     {
       receipt_number,
       employee_ids: [id1, id2],
       details: [{ saledetail_id, quantity }]
     }

[Rails サーバー]

  バリデーション:
    - employee_ids 全員が認証済み + 店舗アクセス権限
    - 返品数量 ≦ 元売上数量
    - 同一 Sale の 2 度返品はエラー

  Transaction:
    1. Refund 作成
    2. RefundDetail 作成（選択した saledetail に紐付け）
    3. 元売上の全アイテムを在庫に戻す
       StoreStock.with_lock do
         increment! quantity
         StockMovement.create!(reason: "return")
       end

  Response: { success, refund_id, refund_receipt_number, total_refund_amount }

[Flutter クライアント]
  ReceiptPrinter.printRefundReceipt() → 返品レシート印刷
```

---

## 20. データフロー — 在庫管理

```
[在庫入出庫]

InventoryInoutView:
  1. JAN コードスキャン（複数商品）
  2. 数量・方向（in/out）入力
  3. 従業員 PIN 認証
  4. POST /api/v1/store_stocks/move
     { employee_id, movements: [{ jan_code, quantity, direction }] }

  Rails:
    各商品を StoreStock.with_lock で in/out
    StockMovement.create!(reason: "manual_in" or "manual_out")

  Response: 各商品の処理結果 + 現在在庫数

[店舗間移動（ダッシュボード）]

  Dashboard::StoreStocksController#transfer:
    from_stock.with_lock → decrement + "transfer_out" movement
    to_stock.with_lock   → increment + "transfer_in" movement
```

---

## 21. 設計上の重要パターン

### 1. 悲観的ロック（Pessimistic Locking）

並行リクエストによる在庫の競合状態を防ぐ。

```ruby
ActiveRecord::Base.transaction do
  store_stock.lock!          # SELECT ... FOR UPDATE
  old_qty = store_stock.quantity
  store_stock.update!(quantity: new_qty)
  StockMovement.create!(quantity_change: new_qty - old_qty)
end
```

適用箇所:
- 売上時の在庫引き落とし（`SalesController#deduct_stock`）
- 在庫入出庫（`StoreStocksController#move`）
- 店舗間移動（`Dashboard::StoreStocksController#transfer`）
- 在庫直接修正（`Dashboard::StoreStocksController#update`）
- レシート連番採番（`PosDevicesController` 内 `pos_token.with_lock`）

### 2. カーソルページネーション（商品同期）

```
クライアント:
  GET /api/v1/products/sync
      → { products: [...100件...], has_more: true, last_updated_at: "...", last_id: 999 }
  GET /api/v1/products/sync?last_updated_at=...&last_id=999
      → { products: [...100件...], has_more: false }
```

中断後も `last_updated_at` + `last_id` から再開可能。大量商品も安全に同期。

### 3. Fire-and-Forget 非同期保存（飲食店モード）

```dart
// スキャン後に UI をブロックせずサーバーに保存
void _triggerTableSave() {
  TableOrderApi.saveItems(tableNumber, _scannedItems).catchError((_) {
    // エラーは無視（ローカルは既に更新済み）
  });
}
```

### 4. JSONB による柔軟な設定管理

`Provisioning.store_context` と `hardware_settings` を JSONB で保持することで、スキーマ変更なしに設定項目を追加できる。

```json
{
  "store_context": {
    "store_id": 1,
    "store_name": "渋谷店",
    "store_mode": "restaurant"
  },
  "hardware_settings": {
    "printer_ip": "192.168.1.100",
    "drawer_kick_command": "27,112,0,50,250"
  }
}
```

### 5. インメモリフォールバック（卓注文・保留注文）

```
API 成功 → サーバーに保存（全 POS 共有）
API 失敗 → TableOrderStore / HoldOrderStore（端末内メモリ）
```

ネットワーク障害時も業務継続可能。再接続後は API 経由の最新データを優先する。

### 6. 税額の逆算

```dart
// 税込価格から税額を逆算（切り捨て）
final exTax = (subtotal * 100 / (100 + taxRate)).floor();
final taxAmount = subtotal - exTax;
```

```ruby
# Rails 側でも同じロジック
ex_tax = (subtotal * 100 / (100 + tax_rate)).floor
tax_amount = subtotal - ex_tax
```

### 7. 監査証跡（Audit Trail）

```
全在庫変動 → StockMovement（reason + sale/employee/pos_token 参照付き）
全売上     → Sale + Saledetail + SalePayment
全返品     → Refund + RefundDetail（元 Saledetail 参照付き）
全レジ操作 → CashLog（金種レベルの詳細）
```

---

*このドキュメントは OnLiPos リポジトリの全コードを分析して作成されました。*
*最終更新: 2026-04-12（ホスト・クライアント型 POS モード追加）*
