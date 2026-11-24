# ダッシュボードのメニュー（サイドメニュー・パンくず・スマートフォンの下部メニュー）と、ページ見出しの共通部品。
# メニューに項目を足すときは dashboard_nav_groups に追加する。
module NavigationHelper
  NavItem = Struct.new(:label, :path, :controller, :badge, :keywords, keyword_init: true)
  NavGroup = Struct.new(:key, :label, :icon, :items, keyword_init: true)

  def dashboard_nav_groups
    @dashboard_nav_groups ||= [
      nav_group(:sales, "売上を見る", :chart, [
        nav("売上一覧", dashboard_sales_path, "sales", keywords: "会計 レシート 取引", also: "sale_details"),
        nav("要確認の会計", dashboard_sale_reviews_path, "sale_reviews", badge: pending_review_count, keywords: "オフライン 確認"),
        nav("売上レポート", dashboard_reports_path, "reports", keywords: "集計 日次 月次 税率"),
        nav("売上分析", dashboard_analytics_path, "analytics", keywords: "グラフ 時間帯 商品別"),
        nav("返品一覧", dashboard_refunds_path, "refunds", keywords: "返金")
      ]),
      nav_group(:register, "レジのお金・記録", :register, [
        nav("レジ精算（Z）", dashboard_register_sessions_path, "register_sessions", keywords: "締め 過不足 日計"),
        nav("レジ金の履歴", dashboard_cash_logs_path, "cash_logs", keywords: "開設 点検 釣銭"),
        nav("電子ジャーナル", dashboard_journals_path, "journals", keywords: "控え 改ざん 記録")
      ]),
      nav_group(:products, "商品の管理", :tag, [
        nav("商品", dashboard_products_path, "products", keywords: "CSV 登録 価格"),
        nav("カテゴリ", dashboard_product_categories_path, "product_categories", keywords: "分類"),
        nav("セット商品", dashboard_product_bundles_path, "product_bundles", keywords: "まとめ"),
        nav("オプション", dashboard_option_groups_path, "option_groups", keywords: "トッピング サイズ"),
        nav("価格・税率の予約", dashboard_scheduled_changes_path, "scheduled_changes", keywords: "消費税 値上げ 変更")
      ]),
      nav_group(:customers, "お客様・販促", :gift, [
        nav("会員", dashboard_customers_path, "customers", keywords: "顧客 ポイント 掛売"),
        nav("自動値引き", dashboard_promotions_path, "promotions", keywords: "セール タイムセール まとめ買い"),
        nav("クーポン", dashboard_coupons_path, "coupons", keywords: "割引"),
        nav("予約", dashboard_reservations_path, "reservations", keywords: "来店 席")
      ]),
      nav_group(:stock, "在庫・仕入れ", :box, [
        nav("店舗在庫", dashboard_store_stocks_path, "store_stocks", keywords: "数量 移動"),
        nav("在庫不足", dashboard_low_stocks_path, "low_stocks", keywords: "警告 欠品"),
        nav("入出庫の履歴", dashboard_stock_movements_path, "stock_movements", keywords: "在庫移動"),
        nav("棚卸", dashboard_stocktakes_path, "stocktakes", keywords: "実数 差異"),
        nav("発注・入荷", dashboard_purchase_orders_path, "purchase_orders", keywords: "仕入"),
        nav("仕入先", dashboard_suppliers_path, "suppliers", keywords: "取引先")
      ]),
      nav_group(:stores, "店舗・スタッフ", :store, [
        nav("店舗", dashboard_stores_path, "stores", keywords: "住所 店舗別価格"),
        nav("POS端末", dashboard_pos_devices_path, "pos_devices", keywords: "レジ パスワード 停止"),
        nav("端末の初期設定", dashboard_provisionings_path, "provisionings", keywords: "プロビジョニング プリンター"),
        nav("従業員", dashboard_employees_path, "employees", keywords: "スタッフ 権限 PIN"),
        nav("勤怠", dashboard_attendances_path, "attendances", keywords: "出勤 退勤 打刻"),
        nav("卓・セルフ注文", dashboard_table_codes_path, "table_codes", keywords: "QRコード 厨房 テーブル")
      ]),
      nav_group(:integrations, "会計ソフト・連携", :plug, [
        nav("会計ソフト出力", dashboard_accounting_export_path, "accounting_exports", keywords: "仕訳 freee 弥生 CSV"),
        (nav("APIキー", dashboard_api_keys_path, "api_keys", keywords: "外部連携") if role_at_least?(:owner)),
        (nav("Webhook", dashboard_webhooks_path, "webhooks", keywords: "通知 外部連携") if role_at_least?(:owner))
      ]),
      nav_group(:settings, "設定", :gear, [
        (nav("お店の基本設定", dashboard_account_settings_path, "account_settings", keywords: "インボイス 登録番号 レシート ポイント") if role_at_least?(:manager)),
        (nav("メンバー", dashboard_members_path, "members", keywords: "管理者 役割 追加") if role_at_least?(:owner)),
        (nav("操作履歴", dashboard_audit_logs_path, "audit_logs", keywords: "ログ 監査") if role_at_least?(:owner)),
        nav("セキュリティ", dashboard_security_path, "security", keywords: "2段階認証 パスキー リカバリーコード"),
        nav("マイページ", edit_user_registration_path, "registrations", keywords: "氏名 メール パスワード")
      ])
    ]
  end

  # スマートフォンの画面下に固定表示する、よく使う項目
  def dashboard_bottom_nav
    [ [ "ホーム", dashboard_root_path, :home, %w[dashboards] ], [ "売上", dashboard_sales_path, :chart, %w[sales sale_details sale_reviews reports analytics refunds] ],
      [ "商品", dashboard_products_path, :tag, %w[products product_categories product_bundles option_groups scheduled_changes] ],
      [ "在庫", dashboard_store_stocks_path, :box, %w[store_stocks low_stocks stock_movements stocktakes purchase_orders suppliers] ] ]
  end

  def current_nav_group = dashboard_nav_groups.find { |g| g.items.any? { |i| nav_active?(i) } }
  def current_nav_item = current_nav_group&.items&.find { |i| nav_active?(i) }
  def nav_active?(item) = item.controller.include?(controller_name)

  # ページの見出し。<title> とパンくずも合わせて設定する。
  # back: true なら一覧へ戻るリンクを出す（[表示名, パス] で指定も可）。ブロックには右側の操作ボタンを書く
  def page_header(title, lead: nil, back: nil, &block)
    content_for(:title, title)
    back = [ "#{current_nav_item.label}に戻る", current_nav_item.path ] if back == true && current_nav_item
    actions = block ? capture(&block) : nil
    render "dashboard/shared/page_header", title: title, lead: lead, back: back.presence, actions: actions.presence
  end

  # 期間をワンクリックで選べるリンク（検索条件 from / to を持つ一覧で使う）
  def period_chips(extra = {})
    today = Date.current
    ranges = { "今日" => [ today, today ], "昨日" => [ today - 1, today - 1 ], "過去7日" => [ today - 6, today ],
               "今月" => [ today.beginning_of_month, today ], "先月" => [ today.prev_month.beginning_of_month, today.prev_month.end_of_month ] }
    selected = [ (@from || params[:from]).to_s, (@to || params[:to]).to_s ]
    query = request.query_parameters.except("page", "from", "to").merge(extra)
    content_tag(:div, class: "chips", role: "group", "aria-label": "期間をえらぶ") do
      safe_join(ranges.map do |label, (from, to)|
        current = selected == [ from.to_s, to.to_s ]
        link_to(label, url_for(query.merge(from: from, to: to)), class: [ "chip", ("active" if current) ], aria: { current: (current || nil) })
      end)
    end
  end

  # 「わからない」をその場で解消するための短い説明（開閉式）
  def help_note(title, &block)
    content_tag(:details, class: "help-note") do
      content_tag(:summary, safe_join([ icon(:help, size: 18), " ", title ])) + content_tag(:div, capture(&block), class: "help-note-body")
    end
  end

  private

  def nav_group(key, label, icon, items) = NavGroup.new(key: key, label: label, icon: icon, items: items.compact)

  def nav(label, path, controller, badge: nil, keywords: nil, also: nil)
    NavItem.new(label: label, path: path, controller: [ controller, also ].compact, badge: badge, keywords: keywords)
  end

  def pending_review_count
    @pending_review_count ||= Sale.where(user: current_account).needing_review.count
  end
end
