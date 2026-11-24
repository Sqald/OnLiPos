# クーポン
class Dashboard::CouponsController < Dashboard::ResourceController
  manages Coupon, title: "クーポン", order: { id: :desc },
    description: "会計の小計から割り引きます。レジでコードを入力すると、値引き権限がなくても利用できます。",
    columns: { "コード" => :code, "名称" => :name, "割引" => ->(r, v) { r.discount_percent? ? "#{r.discount_value}%" : v.yen(r.discount_value) },
               "最低金額" => ->(r, v) { v.yen(r.min_total) }, "期間" => ->(r, _) { "#{r.starts_on} 〜 #{r.ends_on}" },
               "利用" => ->(r, _) { "#{r.used_count}#{" / #{r.usage_limit}" if r.usage_limit}" }, "状態" => ->(r, v) { v.badge(r.active ? "有効" : "停止", r.active) } },
    fields: [ field(:code, "コード（半角英数字）", required: true, maxlength: 32), field(:name, "名称", required: true),
              field(:discount_type, "割引の種類", :select, choices: [ [ "金額", "amount" ], [ "パーセント", "percent" ] ]), field(:discount_value, "割引額 / 割引率", :number, min: 1, required: true),
              field(:min_total, "最低金額", :number, min: 0), field(:starts_on, "開始日", :date), field(:ends_on, "終了日", :date),
              field(:usage_limit, "利用回数の上限（空欄 = なし）", :number, min: 1), field(:active, "有効", :checkbox) ]
end
