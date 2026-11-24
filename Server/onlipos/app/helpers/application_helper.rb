# アプリケーション全体で共有するビューヘルパー
module ApplicationHelper
  def yen(amount)
    amount.nil? ? "-" : number_to_currency(amount, unit: "¥", precision: 0, format: "%u%n", negative_format: "-%u%n")
  end

  def datetime(time)
    time ? l(time.in_time_zone, format: "%Y/%m/%d %H:%M") : "-"
  end

  # 見出し・行（セルの配列の配列）から一覧表を作る。空なら empty を表示する
  def data_table(headers, rows, empty: "データがありません。")
    return content_tag(:div, content_tag(:p, empty), class: "empty-message") if rows.blank?

    content_tag(:div, class: "card card-table") do
      content_tag(:table, class: "data-table") do
        safe_join([
          content_tag(:thead, content_tag(:tr, safe_join(headers.map { |h| content_tag(:th, h) }))),
          content_tag(:tbody, safe_join(rows.map { |cells| content_tag(:tr, safe_join(cells.map { |c| content_tag(:td, c) })) }))
        ])
      end
    end
  end

  # 見出しと値の組（縦並びの表）
  def detail_table(pairs)
    content_tag(:table, class: "data-table") do
      content_tag(:tbody, safe_join(pairs.map { |label, value| content_tag(:tr, content_tag(:th, label) + content_tag(:td, value)) }))
    end
  end

  def badge(text, active = true)
    content_tag(:span, text, class: "status-badge #{active ? 'status-active' : 'status-inactive'}")
  end

  def form_errors(record)
    return if record.errors.empty?

    content_tag(:div, safe_join(record.errors.full_messages.map { |m| content_tag(:p, m) }), class: "alert")
  end
end
