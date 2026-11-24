# 売上分析（ダッシュボード「売上分析」画面）の集計エンジン。
#
# POSの基本要素を軸（ディメンション）として、任意の1軸または2軸のクロス集計を行う。
#   いつ   : 日別 / 週別 / 月別 / 曜日別 / 時間帯別（営業日 business_date・販売時刻 sold_at 基準）
#   どこで : 店舗別 / レジ（POS端末）別
#   誰が   : 従業員（担当者）別
#   何を   : 商品別 / カテゴリ別
#   どうやって : 支払方法別（会計の主たる支払方法）
#   いくらで   : 単価帯別
#   誰に   : 客層キー（性別・年代）別
# 指標は 売上金額（税込）・販売点数・客数（会計件数）・客単価・平均単価・値引額・粗利（税抜売上 − 原価。原価未登録の明細は含めない）。
#
# 集計の単位は明細行。売上明細（取消=VOID を除く）と、返品明細（マイナス値）を UNION ALL した
# 仮想テーブル lines を作り、そこに GROUP BY をかける。返品の帰属は次の通り:
#   いつ・どこで = 返品を処理した営業日・店舗・レジ（会計上の計上日）
#   誰が・どうやって・誰に・何を = 元の売上の担当者・支払方法・客層・商品
# 「客数」は COUNT(DISTINCT 会計ID) のため単純合計できない。合計行・その他行も SQL で
# 再集計して正しい値を出す（行×列の合算はしない）。
class SalesAnalysis
  OTHER_KEY = "__other__".freeze
  NULL_KEY  = "__null__".freeze

  WEEKDAY_LABELS = %w[月 火 水 木 金 土 日].freeze # ISODOW 1..7
  PRICE_BANDS = [
    [ 100, "〜99円" ], [ 300, "100〜299円" ], [ 500, "300〜499円" ], [ 1000, "500〜999円" ],
    [ 3000, "1,000〜2,999円" ], [ 5000, "3,000〜4,999円" ], [ 10_000, "5,000〜9,999円" ], [ nil, "10,000円〜" ]
  ].freeze
  PAYMENT_LABELS = PaymentMethods::LABELS_BY_CODE
  GENDER_LABELS  = { "0" => "男性", "1" => "女性", "2" => "その他" }.freeze
  AGE_LABELS     = { "0" => "〜19歳", "1" => "20代", "2" => "30代", "3" => "40代", "4" => "50代", "5" => "60歳〜" }.freeze

  PRICE_BAND_SQL = begin
    whens = PRICE_BANDS.each_with_index.filter_map { |(limit, _), i| "WHEN lines.unit_price < #{limit} THEN #{i}" if limit }
    "(CASE #{whens.join(' ')} ELSE #{PRICE_BANDS.size - 1} END)"
  end.freeze

  # kind: :time（期間で欠番を埋める時系列）/ :ordinal（自然順の段階）/ :category（指標順に並べる分類）
  # element: POSの基本要素のどれに当たるか（画面のグルーピング用）
  DIMENSIONS = {
    "day"        => { label: "日別",       element: "いつ",   kind: :time,     sql: "lines.business_date::text" },
    "week"       => { label: "週別",       element: "いつ",   kind: :time,     sql: "date_trunc('week', lines.business_date)::date::text" },
    "month"      => { label: "月別",       element: "いつ",   kind: :time,     sql: "to_char(lines.business_date, 'YYYY-MM')" },
    "weekday"    => { label: "曜日別",     element: "いつ",   kind: :ordinal,  sql: "EXTRACT(ISODOW FROM lines.business_date)::int::text" },
    "hour"       => { label: "時間帯別",   element: "いつ",   kind: :ordinal,  sql: "EXTRACT(HOUR FROM lines.local_at)::int::text" },
    "store"      => { label: "店舗別",     element: "どこで", kind: :category, sql: "lines.store_id::text" },
    "pos"        => { label: "レジ別",     element: "どこで", kind: :category, sql: "lines.pos_token_id::text" },
    "employee"   => { label: "従業員別",   element: "誰が",   kind: :category, sql: "lines.employee_id::text" },
    "product"    => { label: "商品別",     element: "何を",   kind: :category, sql: "lines.product_id::text" },
    "category"   => { label: "カテゴリ別", element: "何を",   kind: :category, sql: "lines.category_id::text" },
    "payment"    => { label: "支払方法別", element: "どうやって", kind: :category, sql: "lines.payment_method::text" },
    "price_band" => { label: "単価帯別",   element: "いくらで",   kind: :ordinal,  sql: "#{PRICE_BAND_SQL}::text" },
    "gender"     => { label: "性別",       element: "誰に",   kind: :category, sql: "lines.customer_gender::text" },
    "age_group"  => { label: "年代別",     element: "誰に",   kind: :ordinal,  sql: "lines.customer_age_group::text" }
  }.freeze

  # additive: 行・列方向に足し合わせられる指標か（積み上げグラフ・構成比はこれのみ）
  METRICS = {
    "amount"     => { label: "売上金額",  unit: :yen,   additive: true },
    "quantity"   => { label: "販売点数",  unit: :count, additive: true },
    "tickets"    => { label: "客数（会計件数）", unit: :count, additive: false },
    "avg_ticket" => { label: "客単価",    unit: :yen,   additive: false },
    "avg_price"  => { label: "平均単価",  unit: :yen,   additive: false },
    "discount"   => { label: "値引額",    unit: :yen,   additive: true },
    "profit"     => { label: "粗利（税抜。原価を登録した商品のみ）", unit: :yen, additive: true }
  }.freeze

  # 絞り込み条件（パラメータ名 => lines の列）
  FILTERS = {
    store_id: "store_id", pos_token_id: "pos_token_id", employee_id: "employee_id",
    product_id: "product_id", category_id: "category_id", payment_method: "payment_method"
  }.freeze

  MAX_ROWS = 200
  MAX_FILL_DAYS = 400

  Cell = Struct.new(:amount, :quantity, :tickets, :discount, :profit, :refund_amount, :gross_amount, keyword_init: true) do
    def self.zero = new(amount: 0, quantity: 0, tickets: 0, discount: 0, profit: 0, refund_amount: 0, gross_amount: 0)

    def value(metric)
      case metric
      when "avg_ticket" then tickets.positive? ? (amount.to_f / tickets).round : 0
      when "avg_price"  then quantity.positive? ? (amount.to_f / quantity).round : 0
      else public_send(metric)
      end
    end
  end

  Row = Struct.new(:key, :label, :total, :cells, :other_count, keyword_init: true)

  attr_reader :user, :from, :to, :row_dim, :col_dim, :metric, :filters, :include_refunds, :row_limit

  def initialize(user:, from:, to:, row_dim: "day", col_dim: nil, metric: "amount", filters: {},
                 include_refunds: true, row_limit: 30)
    @user = user
    @from = from
    @to = to
    @row_dim = DIMENSIONS.key?(row_dim.to_s) ? row_dim.to_s : "day"
    @col_dim = DIMENSIONS.key?(col_dim.to_s) && col_dim.to_s != @row_dim ? col_dim.to_s : nil
    @metric = METRICS.key?(metric.to_s) ? metric.to_s : "amount"
    @filters = filters.to_h.symbolize_keys.slice(*FILTERS.keys).compact_blank
    @include_refunds = include_refunds
    @row_limit = row_limit.to_i.clamp(5, MAX_ROWS)
  end

  def row_dimension = DIMENSIONS[row_dim]
  def col_dimension = col_dim && DIMENSIONS[col_dim]
  def metric_info = METRICS[metric]
  def cross? = col_dim.present?

  # 期間全体の合計（KPI）
  def totals
    @totals ||= aggregate([])[[]] || Cell.zero
  end

  # 取消（VOID）の件数・金額（売上からは除外済み。参考として別掲する）
  def void_summary
    @void_summary ||= begin
      scope = Sale.where(user_id: user.id, status: Sale.statuses[:voided], business_date: from..to)
      scope = scope.where(store_id: filters[:store_id]) if filters[:store_id]
      scope = scope.where(pos_token_id: filters[:pos_token_id]) if filters[:pos_token_id]
      scope = scope.where(employee_id: filters[:employee_id]) if filters[:employee_id]
      { count: scope.count, amount: scope.sum(:total_amount) }
    end
  end

  # 同じ長さの直前期間の合計（前期間比の算出用）
  def previous_totals
    @previous_totals ||= begin
      length = (to - from).to_i + 1
      self.class.new(user: user, from: from - length, to: from - 1, row_dim: row_dim, metric: metric,
                     filters: filters, include_refunds: include_refunds).totals
    end
  end

  # 列（2軸目）の見出し: [[key, label], ...]。上位以外は「その他」にまとめる
  def columns
    return [] unless cross?
    compute
    @columns
  end

  # 行: Row の配列（行キー・ラベル・行合計・列ごとのセル）
  def rows
    compute
    @rows
  end

  def column_totals
    compute
    @column_totals
  end

  private

  def compute
    return if @rows

    row_totals = aggregate([ row_expr ]).transform_keys(&:first)
    row_keys = order_keys(row_dim, row_totals)
    row_cap = DIMENSIONS[row_dim][:kind] == :category ? row_limit : MAX_FILL_DAYS * 2
    top_rows, folded_rows = fold(row_dim, row_keys, row_cap)

    if cross?
      col_totals = aggregate([ col_expr ]).transform_keys(&:first)
      col_keys = order_keys(col_dim, col_totals)
      col_cap = DIMENSIONS[col_dim][:kind] == :category ? 10 : 31
      top_cols, folded_cols = fold(col_dim, col_keys, col_cap)
    end

    frow = folded_rows ? folded_expr(row_expr, top_rows) : row_expr
    if folded_rows
      row_totals = row_totals.slice(*top_rows).merge(aggregate([ frow ]).transform_keys(&:first).slice(OTHER_KEY))
    end
    display_rows = top_rows + (folded_rows ? [ OTHER_KEY ] : [])

    if cross?
      fcol = folded_cols ? folded_expr(col_expr, top_cols) : col_expr
      if folded_cols
        col_totals = col_totals.slice(*top_cols).merge(aggregate([ fcol ]).transform_keys(&:first).slice(OTHER_KEY))
      end
      display_cols = top_cols + (folded_cols ? [ OTHER_KEY ] : [])
      cells = aggregate([ frow, fcol ])
      @columns = display_cols.map { |k| [ k, label_for(col_dim, k, other_count: (col_keys.size - top_cols.size)) ] }
      @column_totals = display_cols.index_with { |k| col_totals[k] || Cell.zero }
    else
      cells = {}
      @columns = []
      @column_totals = {}
    end

    hidden_rows = row_keys.size - top_rows.size
    @rows = display_rows.map do |rk|
      Row.new(
        key: rk,
        label: label_for(row_dim, rk, other_count: hidden_rows),
        total: row_totals[rk] || Cell.zero,
        cells: (cross? ? display_cols.index_with { |ck| cells[[ rk, ck ]] || Cell.zero } : {}),
        other_count: (rk == OTHER_KEY ? hidden_rows : nil)
      )
    end
  end

  def row_expr = "COALESCE(#{DIMENSIONS[row_dim][:sql]}, '#{NULL_KEY}')"
  def col_expr = "COALESCE(#{DIMENSIONS[col_dim][:sql]}, '#{NULL_KEY}')"

  # 上位キー以外を「その他」に寄せる式（キーは SQL 文字列リテラルとしてクオートする）
  def folded_expr(expr, keep_keys)
    quoted = keep_keys.map { |k| ActiveRecord::Base.connection.quote(k) }
    return "'#{OTHER_KEY}'" if quoted.empty?
    "(CASE WHEN #{expr} IN (#{quoted.join(', ')}) THEN #{expr} ELSE '#{OTHER_KEY}' END)"
  end

  # 表示順: 時系列・段階は自然順（期間内の欠番を0で埋める）、分類は選択指標の降順
  def order_keys(dim, totals)
    case DIMENSIONS[dim][:kind]
    when :time
      keys = (fill_keys(dim) | totals.keys).sort
      move_null_last(keys)
    when :ordinal
      keys = (fill_keys(dim) | totals.keys)
      move_null_last(keys.sort_by { |k| k == NULL_KEY ? Float::INFINITY : k.to_i })
    else
      keys = totals.keys.sort_by { |k| [ -totals[k].value(metric), k ] }
      move_null_last(keys)
    end
  end

  def move_null_last(keys)
    keys.include?(NULL_KEY) ? (keys - [ NULL_KEY ]) + [ NULL_KEY ] : keys
  end

  def fill_keys(dim)
    days = (to - from).to_i + 1
    case dim
    when "day"   then days <= MAX_FILL_DAYS ? (from..to).map(&:to_s) : []
    when "week"  then days <= MAX_FILL_DAYS * 7 ? (from..to).map { |d| d.beginning_of_week.to_s }.uniq : []
    when "month" then (from..to).map { |d| d.strftime("%Y-%m") }.uniq
    when "weekday" then (1..7).map(&:to_s)
    else []
    end
  end

  # 表示件数を超える分を「その他」へ。時系列・段階は件数上限まで（通常はすべて）表示する
  def fold(_dim, keys, cap)
    return [ keys, false ] if keys.size <= cap
    [ keys.first(cap), true ]
  end

  # 指定式で GROUP BY し、{ [キー...] => Cell } を返す
  def aggregate(group_exprs)
    selects = group_exprs.map { |e| Arel.sql(e) } + [
      Arel.sql("COALESCE(SUM(lines.amount), 0)"),
      Arel.sql("COALESCE(SUM(lines.qty), 0)"),
      Arel.sql("COUNT(DISTINCT lines.sale_id) FILTER (WHERE lines.kind = 'sale')"),
      Arel.sql("COALESCE(SUM(lines.discount), 0)"),
      Arel.sql("COALESCE(SUM(lines.profit), 0)"),
      Arel.sql("COALESCE(SUM(-lines.amount) FILTER (WHERE lines.kind = 'refund'), 0)"),
      Arel.sql("COALESCE(SUM(lines.amount) FILTER (WHERE lines.kind = 'sale'), 0)")
    ]
    relation = filtered_lines
    relation = relation.group(*group_exprs.map { |e| Arel.sql(e) }) if group_exprs.any?
    n = group_exprs.size
    relation.pluck(*selects).each_with_object({}) do |row, h|
      row = Array(row)
      keys = row.first(n)
      amount, qty, tickets, discount, profit, refund, gross = row.drop(n).map(&:to_i)
      h[keys] = Cell.new(amount: amount, quantity: qty, tickets: tickets, discount: discount, profit: profit,
                         refund_amount: refund, gross_amount: gross)
    end
  end

  def filtered_lines
    relation = Sale.unscoped.from(lines_source)
    filters.each do |key, value|
      column = FILTERS[key]
      relation = value.to_s == NULL_KEY ? relation.where("lines.#{column} IS NULL") : relation.where("lines.#{column} = ?", value.to_i)
    end
    relation
  end

  # 売上明細（+ 返品明細をマイナスで）を1つの明細テーブル lines にまとめたサブクエリ。
  # 各 SELECT は sanitize_sql_array（プレースホルダ）と定数のみで組み立て、ユーザー入力を直接埋め込まない
  def lines_source
    sale_sql, refund_sql = lines_sqls
    node = include_refunds ? Arel::Nodes::UnionAll.new(Arel.sql(sale_sql), Arel.sql(refund_sql)) : Arel::Nodes::Grouping.new(Arel.sql(sale_sql))
    Arel::Nodes::TableAlias.new(node, "lines")
  end

  def lines_sqls
    tz = Time.zone.tzinfo.name
    # 外税明細の subtotal は税抜のため、税込に揃える（明細ごとの参考税額を加算）
    sale_amount = "(sd.subtotal + CASE WHEN sd.tax_type = #{Saledetail.tax_types[:exclusive]} THEN sd.tax_amount ELSE 0 END)"
    refund_amount = "(rd.subtotal + CASE WHEN sd.tax_type = #{Saledetail.tax_types[:exclusive]} THEN rd.tax_amount ELSE 0 END)"

    # 原価の個数。量り売りは原価も100gあたりとして扱う
    cost_units = "(CASE WHEN sd.weight_grams IS NULL THEN sd.quantity ELSE sd.weight_grams / 100.0 END)"

    sale_part = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, { uid: user.id, completed: Sale.statuses[:completed], from: from, to: to, tz: tz } ])
      SELECT 'sale' AS kind, s.id AS sale_id, s.business_date,
             (COALESCE(s.sold_at, s.created_at) AT TIME ZONE 'UTC' AT TIME ZONE :tz) AS local_at,
             s.store_id, s.pos_token_id, s.employee_id, sd.product_id, p.product_category_id AS category_id,
             s.payment_method, s.customer_gender, s.customer_age_group,
             sd.quantity AS qty, sd.unit_price, #{sale_amount} AS amount, sd.discount_amount AS discount,
             (#{sale_amount} - sd.tax_amount - sd.cost_price * #{cost_units}) AS profit
        FROM saledetails sd
        JOIN sales s ON s.id = sd.sale_id
        LEFT JOIN products p ON p.id = sd.product_id
       WHERE s.user_id = :uid AND s.status = :completed AND s.business_date BETWEEN :from AND :to
    SQL

    refund_part = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, { uid: user.id, from: from, to: to, tz: tz } ])
      SELECT 'refund' AS kind, r.sale_id, r.business_date,
             (COALESCE(r.refunded_at, r.created_at) AT TIME ZONE 'UTC' AT TIME ZONE :tz) AS local_at,
             r.store_id, r.pos_token_id, s.employee_id, rd.product_id, p.product_category_id AS category_id,
             s.payment_method, s.customer_gender, s.customer_age_group,
             -rd.quantity AS qty, rd.unit_price, -#{refund_amount} AS amount, 0 AS discount,
             -(#{refund_amount} - rd.tax_amount - sd.cost_price * rd.quantity * #{cost_units} / NULLIF(sd.quantity, 0)) AS profit
        FROM refund_details rd
        JOIN refunds r ON r.id = rd.refund_id
        JOIN sales s ON s.id = r.sale_id
        JOIN saledetails sd ON sd.id = rd.saledetail_id
        LEFT JOIN products p ON p.id = rd.product_id
       WHERE r.user_id = :uid AND r.business_date BETWEEN :from AND :to
    SQL
    [ sale_part, refund_part ]
  end

  # キーを表示ラベルに変換する
  def label_for(dim, key, other_count: 0)
    return "その他（#{other_count}件）" if key == OTHER_KEY
    return null_label(dim) if key == NULL_KEY

    case dim
    when "day"
      d = Date.parse(key)
      "#{d.strftime('%Y-%m-%d')}(#{WEEKDAY_LABELS[d.cwday - 1]})"
    when "week"  then "#{key}〜"
    when "month" then key.sub("-", "年") + "月"
    when "weekday" then "#{WEEKDAY_LABELS[key.to_i - 1]}曜"
    when "hour" then "#{key.to_i}時台"
    when "price_band" then PRICE_BANDS.dig(key.to_i, 1) || key
    when "payment" then PAYMENT_LABELS[key] || key
    when "gender" then GENDER_LABELS[key] || key
    when "age_group" then AGE_LABELS[key] || key
    else lookup_names(dim)[key.to_i] || "(削除済み ##{key})"
    end
  end

  def null_label(dim)
    case dim
    when "employee" then "担当者不明"
    when "category" then "未分類"
    when "pos" then "管理画面登録"
    when "gender", "age_group" then "未入力"
    else "不明"
    end
  end

  def lookup_names(dim)
    @lookup_names ||= {}
    @lookup_names[dim] ||=
      case dim
      when "store" then user.stores.pluck(:id, :name).to_h
      when "pos" then PosToken.joins(:store).where(stores: { user_id: user.id })
                              .pluck(:id, Arel.sql("stores.name || ' / ' || COALESCE(pos_tokens.name, pos_tokens.ascii_name)")).to_h
      when "employee" then user.employees.pluck(:id, :name, :code).to_h { |id, name, code| [ id, "#{name.presence || code}（#{code}）" ] }
      when "product" then user.products.pluck(:id, :name, :code).to_h { |id, name, code| [ id, "#{name}（#{code}）" ] }
      when "category" then ProductCategory.where(user_id: user.id).pluck(:id, :name).to_h
      else {}
      end
  end
end
