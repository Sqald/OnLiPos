# アプリケーション全体で共有するビューヘルパー
module ApplicationHelper
  NUMERIC_CELL = /\A[-+]?¥?-?[\d,]+(\.\d+)?(%|件|個|点|台|日)?\z/

  # 数字だけでも右寄せにしない列（コード・番号など）
  TEXT_HEADER = /コード|番号|ID|JAN|\A卓\z/

  def yen(amount)
    amount.nil? ? "-" : number_to_currency(amount, unit: "¥", precision: 0, format: "%u%n", negative_format: "-%u%n")
  end

  def datetime(time)
    time ? l(time.in_time_zone, format: "%Y/%m/%d %H:%M") : "-"
  end

  # 決済手段の表示（複数の手段を使った会計は内訳を並べる）
  def sale_payment_label(sale)
    return PaymentMethods.label(sale.payment_method) if sale.sale_payments.empty?
    return PaymentMethods.label(sale.sale_payments.first.method) if sale.sale_payments.one?

    safe_join(sale.sale_payments.map { |p| "#{PaymentMethods.label(p.method)} #{yen(p.amount)}" }, tag.br)
  end

  STOCK_REASONS = { "sale" => "販売", "return" => "返品", "void" => "会計の取消", "purchase" => "入荷", "stocktake" => "棚卸", "manual_adjustment" => "手動の変更",
                    "manual_in" => "端末での入庫", "manual_out" => "端末での出庫",
                    "transfer_in" => "店舗間の移動（入）", "transfer_out" => "店舗間の移動（出）" }.freeze

  def stock_reason_label(reason) = STOCK_REASONS.fetch(reason.to_s, reason)

  # 見出し・行（セルの配列の配列）から一覧表を作る。空なら empty を表示する。
  # 金額・件数の列は右寄せにする
  def data_table(headers, rows, empty: "データがありません。", action: nil)
    return empty_message(empty, action: action) if rows.blank?

    numeric = headers.each_index.select { |i| !headers[i].match?(TEXT_HEADER) && rows.all? { |cells| c = cells[i]; c.is_a?(Numeric) || c.nil? || c.to_s == "-" || (c.is_a?(String) && c.match?(NUMERIC_CELL)) } && rows.any? { |cells| cells[i].present? && cells[i].to_s != "-" } }
    content_tag(:div, class: "card card-table") do
      content_tag(:table, class: "data-table") do
        safe_join([
          content_tag(:thead, content_tag(:tr, safe_join(headers.each_with_index.map { |h, i| content_tag(:th, h, class: ("num" if numeric.include?(i) || h == "操作")) }))),
          content_tag(:tbody, safe_join(rows.map { |cells| content_tag(:tr, safe_join(cells.each_with_index.map { |c, i| content_tag(:td, c, class: ("num" if numeric.include?(i))) })) }))
        ])
      end
    end
  end

  # 空の一覧の案内。action に次の操作（リンクなど）を渡せる
  def empty_message(text, action: nil)
    content_tag(:div, class: "card") do
      content_tag(:div, safe_join([ icon(:box, size: 40), tag.p(text), (tag.p(action) if action) ].compact), class: "empty-message")
    end
  end

  # 見出しと値の組（縦並びの表）
  def detail_table(pairs)
    content_tag(:div, class: "card card-table") do
      content_tag(:table, class: "data-table") do
        content_tag(:tbody, safe_join(pairs.map { |label, value| content_tag(:tr, content_tag(:th, label, scope: "row") + content_tag(:td, value.presence || "-")) }))
      end
    end
  end

  # 一覧の行の操作ボタンを並べる
  def row_actions(*items) = content_tag(:div, safe_join(items.compact_blank), class: "row-actions")

  # kind: true（有効）/ false（無効）/ :warning / :danger
  def badge(text, kind = true)
    css = { true => "status-active", false => "status-inactive" }.fetch(kind) { "status-#{kind}" }
    content_tag(:span, text, class: "status-badge #{css}")
  end

  def required_mark = content_tag(:span, "必須", class: "badge-required")
  def optional_mark = content_tag(:span, "任意", class: "badge-optional")

  def result_count(collection) = content_tag(:p, "#{number_with_delimiter(collection.total_count)}件", class: "result-count")

  def form_errors(record)
    return if record.errors.empty?

    content_tag(:div, id: "error_explanation", role: "alert") do
      content_tag(:h2, "入力内容を確認してください（#{record.errors.count}件）") + content_tag(:ul, safe_join(record.errors.full_messages.map { |m| tag.li(m) }))
    end
  end
end
