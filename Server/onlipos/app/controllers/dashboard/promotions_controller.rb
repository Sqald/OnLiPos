# 自動値引き（タイムセール・よりどり・まとめ買い）
class Dashboard::PromotionsController < Dashboard::ResourceController
  WEEKDAYS = %w[日 月 火 水 木 金 土].freeze

  manages Promotion, title: "自動値引き", order: { id: :desc },
    description: "対象の商品をレジに通すと自動で値引きします。端末には次回の同期で反映されます。",
    columns: { "名称" => :name, "種類" => ->(r, _) { Promotion::KIND_LABELS[r.kind] },
               "内容" => ->(r, v) { [ ("#{r.set_quantity}点" unless r.time_sale?), (r.percent_off ? "#{r.percent_off}%引き" : v.yen(r.fixed_price)) ].compact.join(" ") },
               "対象" => ->(r, _) { [ r.product_category&.name, ("商品#{r.products.size}点" if r.products.any?) ].compact.join("、") },
               "期間" => ->(r, _) { "#{r.starts_on} 〜 #{r.ends_on}" }, "状態" => ->(r, v) { v.badge(r.active ? "有効" : "停止", r.active) } },
    fields: [ field(:name, "名称", required: true), field(:kind, "種類", :select, choices: Promotion::KIND_LABELS.map { |k, v| [ v, k ] }),
              field(:percent_off, "割引率（%）", :number, min: 1, max: 100), field(:fixed_price, "販売価格 / セット価格（円）", :number, min: 0),
              field(:set_quantity, "点数（よりどり・まとめ買い）", :number, min: 2),
              field(:product_category_id, "対象カテゴリ", :select, blank: "指定しない", choices: -> { current_account.product_categories.order(:display_order).pluck(:name, :id) }),
              field(:product_ids, "対象商品", :checkboxes, choices: -> { current_account.products.active.order(:code).limit(500).map { |p| [ "#{p.code} #{p.name}", p.id ] } }),
              field(:starts_on, "開始日", :date), field(:ends_on, "終了日", :date), field(:start_time, "開始時刻（HH:MM）"), field(:end_time, "終了時刻（HH:MM）"),
              field(:weekdays, "曜日（選択なし = 毎日）", :checkboxes, choices: WEEKDAYS.each_with_index.map { |w, i| [ w, i ] }), field(:active, "有効", :checkbox) ]
end
