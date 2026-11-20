# 売上分析画面のグラフをサーバー側で SVG として描画するヘルパー。
# CSP（script-src 'self'）の下で外部ライブラリなしに表示でき、Turbo の画面遷移でも崩れない。
# ホバー時の値表示は SVG の <title>（ブラウザ標準のツールチップ）で行い、
# 同じ数値は必ず下の集計表にも出す（グラフだけに情報を持たせない）。
module AnalyticsChartsHelper
  # カテゴリ色（固定順。順位ではなく系列の並び順に割り当てる）。9系列目以降は「その他」に畳む
  SERIES_COLORS = %w[#2a78d6 #eb6834 #1baf7a #eda100 #e87ba4 #008300 #6250d6 #e34948].freeze
  OTHER_COLOR = "#a3a29c".freeze
  MAX_SERIES = 7 # + その他 = 8
  # 単一系列・ヒートマップ用の青系シーケンシャル（薄→濃）
  SEQUENTIAL = %w[#cde2fb #b7d3f6 #9ec5f4 #86b6ef #6da7ec #5598e7 #3987e5 #2a78d6 #256abf #1c5cab].freeze
  BAR_COLOR = "#2a78d6".freeze
  GRID_COLOR = "#e6e5e0".freeze
  AXIS_TEXT = "#6b6a65".freeze
  NEGATIVE_COLOR = "#e34948".freeze

  # 値の表示（円 or 件数）
  def analytics_value(value, unit)
    unit == :yen ? "¥#{number_with_delimiter(value.to_i)}" : number_with_delimiter(value.to_i)
  end

  # 軸目盛り用の短縮表記（1.2万 など）
  def analytics_axis_value(value, unit)
    v = value.to_i
    s = if v.abs >= 100_000_000 then "#{trim_num(v / 100_000_000.0)}億"
    elsif v.abs >= 10_000 then "#{trim_num(v / 10_000.0)}万"
    else number_with_delimiter(v)
    end
    unit == :yen ? "¥#{s}" : s
  end

  # 横棒グラフ（分類の比較）。items: [{ label:, value:, href: }]
  def analytics_hbar_chart(items, unit:)
    return analytics_empty_chart if items.empty?

    label_w = 210
    value_w = 96
    width = 820
    bar_area = width - label_w - value_w
    row_h = 26
    top = 6
    height = top + items.size * row_h + 6
    min_v = [ items.map { |i| i[:value] }.min, 0 ].min
    max_v = [ items.map { |i| i[:value] }.max, 0 ].max
    span = (max_v - min_v).nonzero? || 1
    zero_x = label_w + bar_area * (-min_v.to_f / span)

    parts = []
    items.each_with_index do |item, i|
      y = top + i * row_h
      v = item[:value]
      x0 = zero_x
      x1 = label_w + bar_area * ((v - min_v).to_f / span)
      bx, bw = [ x0, x1 ].min, (x1 - x0).abs
      color = v.negative? ? NEGATIVE_COLOR : (item[:color] || BAR_COLOR)
      tip = "#{item[:label]}: #{analytics_value(v, unit)}"
      label = truncate(item[:label].to_s, length: 18)
      label_svg = %(<text x="#{label_w - 8}" y="#{y + 17}" text-anchor="end" class="viz-label">#{h(label)}</text>)
      label_svg = %(<a href="#{h(item[:href])}">#{label_svg}</a>) if item[:href]
      parts << %(<g class="viz-mark"><title>#{h(tip)}</title>)
      parts << %(<rect x="0" y="#{y}" width="#{width}" height="#{row_h}" fill="transparent"/>)
      parts << label_svg
      parts << bar_path(bx, y + 5, bw, row_h - 10, horizontal: true, negative: v.negative?, fill: color) if bw.positive?
      parts << %(<text x="#{[ bx + bw, zero_x ].max + 6}" y="#{y + 17}" class="viz-value">#{h(analytics_value(v, unit))}</text>)
      parts << "</g>"
    end
    parts << %(<line x1="#{zero_x}" y1="#{top}" x2="#{zero_x}" y2="#{height - 6}" stroke="#{AXIS_TEXT}" stroke-width="1"/>)
    svg_wrap(width, height, parts.join, "横棒グラフ")
  end

  # 縦棒グラフ（時系列・段階）。点が多い場合は折れ線にする
  def analytics_column_chart(items, unit:)
    return analytics_empty_chart if items.empty?
    return analytics_line_chart(items, unit: unit) if items.size > 40

    frame = chart_frame(items.map { |i| i[:value] }, unit)
    n = items.size
    slot = frame[:plot_w] / n.to_f
    bar_w = [ [ slot * 0.7, 3 ].max, 48 ].min
    parts = [ frame[:grid] ]
    items.each_with_index do |item, i|
      x = frame[:left] + slot * i
      v = item[:value]
      y_v = frame[:y].call(v)
      y_0 = frame[:y].call(0)
      tip = "#{item[:label]}: #{analytics_value(v, unit)}"
      parts << %(<g class="viz-mark"><title>#{h(tip)}</title>)
      parts << %(<rect x="#{x}" y="#{frame[:top]}" width="#{slot}" height="#{frame[:plot_h]}" fill="transparent"/>)
      bh = (y_0 - y_v).abs
      if bh.positive?
        parts << bar_path(x + (slot - bar_w) / 2, [ y_v, y_0 ].min, bar_w, bh, horizontal: false,
                          negative: v.negative?, fill: v.negative? ? NEGATIVE_COLOR : BAR_COLOR)
      end
      parts << "</g>"
    end
    parts << x_labels(items.map { |i| i[:label] }, frame, slot)
    svg_wrap(frame[:width], frame[:height], parts.join, "縦棒グラフ")
  end

  def analytics_line_chart(items, unit:)
    frame = chart_frame(items.map { |i| i[:value] }, unit)
    n = items.size
    slot = frame[:plot_w] / n.to_f
    pts = items.each_with_index.map { |item, i| [ frame[:left] + slot * (i + 0.5), frame[:y].call(item[:value]) ] }
    y0 = frame[:y].call(0)
    area = "M#{pts.first[0].round(1)},#{y0.round(1)} " + pts.map { |x, y| "L#{x.round(1)},#{y.round(1)}" }.join(" ") +
           " L#{pts.last[0].round(1)},#{y0.round(1)} Z"
    parts = [ frame[:grid] ]
    parts << %(<path d="#{area}" fill="#{BAR_COLOR}" fill-opacity="0.12"/>)
    parts << %(<polyline points="#{pts.map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(' ')}" fill="none" stroke="#{BAR_COLOR}" stroke-width="2" stroke-linejoin="round"/>)
    items.each_with_index do |item, i|
      x, y = pts[i]
      tip = "#{item[:label]}: #{analytics_value(item[:value], unit)}"
      parts << %(<g class="viz-mark viz-point"><title>#{h(tip)}</title>)
      parts << %(<rect x="#{(x - slot / 2).round(1)}" y="#{frame[:top]}" width="#{slot.round(2)}" height="#{frame[:plot_h]}" fill="transparent"/>)
      parts << %(<circle cx="#{x.round(1)}" cy="#{y.round(1)}" r="4" fill="#{BAR_COLOR}" stroke="#fff" stroke-width="2"/>)
      parts << "</g>"
    end
    parts << x_labels(items.map { |i| i[:label] }, frame, slot)
    svg_wrap(frame[:width], frame[:height], parts.join, "折れ線グラフ")
  end

  # 積み上げ棒（クロス集計の構成）。rows: [{ label:, values: [..] }], series: [{ label:, color: }]
  # 積み上げは足し合わせられる指標のみ。マイナス（返品超過）のセルは 0 として描く（表には実数を表示）
  def analytics_stacked_chart(rows, series, unit:, horizontal:)
    return analytics_empty_chart if rows.empty?
    horizontal ? stacked_horizontal(rows, series, unit) : stacked_vertical(rows, series, unit)
  end

  # 系列（列）を最大8系列に畳む。戻り値: [series, rows]
  def analytics_fold_series(analysis)
    cols = analysis.columns
    keep = cols.reject { |k, _| k == SalesAnalysis::OTHER_KEY }.first(MAX_SERIES)
    rest = cols - keep
    series = keep.each_with_index.map { |(_, label), i| { label: label, color: SERIES_COLORS[i] } }
    series << { label: "その他", color: OTHER_COLOR } if rest.any?
    rows = analysis.rows.map do |row|
      values = keep.map { |k, _| row.cells[k].value(analysis.metric) }
      values << rest.sum { |k, _| row.cells[k].value(analysis.metric) } if rest.any?
      { label: row.label, values: values }
    end
    [ series, rows ]
  end

  # ヒートマップのセル背景（最大値に対する割合で濃淡）。戻り値: style 属性の文字列
  def analytics_heat_style(value, max)
    return "" if max.to_i <= 0 || value.to_i <= 0
    idx = ((value.to_f / max) * (SEQUENTIAL.size - 1)).round.clamp(0, SEQUENTIAL.size - 1)
    ink = idx >= 6 ? "#ffffff" : "#0b0b0b"
    "background-color: #{SEQUENTIAL[idx]}; color: #{ink};"
  end

  def analytics_series_color(index, other: false)
    other ? OTHER_COLOR : SERIES_COLORS[index % SERIES_COLORS.size]
  end

  def analytics_empty_chart
    tag.div("この条件の売上データはありません。", class: "viz-empty")
  end

  private

  def trim_num(f)
    f.round(1).to_s.sub(/\.0\z/, "")
  end

  def svg_wrap(width, height, body, label)
    %(<svg class="viz-svg" viewBox="0 0 #{width} #{height}" width="100%" role="img" aria-label="#{h(label)}" preserveAspectRatio="xMinYMin meet">#{body}</svg>).html_safe
  end

  # 縦棒・折れ線の共通枠（Y軸の目盛りとグリッド）
  def chart_frame(values, unit, width: 820, height: 280)
    left = 70
    right = 12
    top = 12
    bottom = 46
    plot_w = width - left - right
    plot_h = height - top - bottom
    min_v = [ values.min || 0, 0 ].min
    max_v = [ values.max || 0, 0 ].max
    max_v = 1 if max_v == min_v
    step = nice_step((max_v - min_v) / 4.0)
    lo = (min_v / step.to_f).floor * step
    hi = (max_v / step.to_f).ceil * step
    hi = lo + step if hi == lo
    y = ->(v) { top + plot_h * (1 - (v - lo).to_f / (hi - lo)) }
    grid = +""
    lo.step(hi, step) do |t|
      yy = y.call(t).round(1)
      stroke = t.zero? ? AXIS_TEXT : GRID_COLOR
      grid << %(<line x1="#{left}" y1="#{yy}" x2="#{width - right}" y2="#{yy}" stroke="#{stroke}" stroke-width="1"/>)
      grid << %(<text x="#{left - 8}" y="#{yy + 4}" text-anchor="end" class="viz-axis">#{h(analytics_axis_value(t, unit))}</text>)
    end
    { width: width, height: height, left: left, top: top, plot_w: plot_w, plot_h: plot_h, y: y, grid: grid }
  end

  def nice_step(raw)
    return 1 if raw <= 0
    mag = 10**Math.log10(raw).floor
    [ 1, 2, 2.5, 5, 10 ].map { |m| m * mag }.find { |s| s >= raw }.then { |s| s < 1 ? 1 : s.ceil }
  end

  # X軸ラベル（重ならないよう間引く）
  def x_labels(labels, frame, slot)
    every = [ (labels.size / 12.0).ceil, 1 ].max
    y = frame[:top] + frame[:plot_h] + 18
    labels.each_with_index.filter_map do |label, i|
      next unless (i % every).zero?
      x = frame[:left] + slot * (i + 0.5)
      %(<text x="#{x.round(1)}" y="#{y}" text-anchor="middle" class="viz-axis">#{h(short_label(label))}</text>)
    end.join
  end

  # 軸に出すラベルを短くする（2026-11-20(金) → 11/20 など）
  def short_label(label)
    s = label.to_s
    if (m = s.match(/\A\d{4}-(\d{2})-(\d{2})(\(.\))?/))
      "#{m[1].to_i}/#{m[2].to_i}"
    else
      truncate(s, length: 10)
    end
  end

  # データ端だけ角丸（半径4px）にした棒。基準線側は直角
  def bar_path(x, y, w, h, horizontal:, negative:, fill:)
    r = [ 4, (horizontal ? h : w) / 2.0, (horizontal ? w : h) ].min
    x, y, w, h = [ x, y, w, h ].map { |v| v.round(2) }
    d =
      if horizontal && !negative # 右端が丸い
        "M#{x},#{y} H#{x + w - r} Q#{x + w},#{y} #{x + w},#{y + r} V#{y + h - r} Q#{x + w},#{y + h} #{x + w - r},#{y + h} H#{x} Z"
      elsif horizontal # 左端が丸い
        "M#{x + w},#{y} H#{x + r} Q#{x},#{y} #{x},#{y + r} V#{y + h - r} Q#{x},#{y + h} #{x + r},#{y + h} H#{x + w} Z"
      elsif !negative # 上端が丸い
        "M#{x},#{y + h} V#{y + r} Q#{x},#{y} #{x + r},#{y} H#{x + w - r} Q#{x + w},#{y} #{x + w},#{y + r} V#{y + h} Z"
      else # 下端が丸い
        "M#{x},#{y} V#{y + h - r} Q#{x},#{y + h} #{x + r},#{y + h} H#{x + w - r} Q#{x + w},#{y + h} #{x + w},#{y + h - r} V#{y} Z"
      end
    %(<path d="#{d}" fill="#{fill}"/>)
  end

  def stacked_vertical(rows, series, unit)
    totals = rows.map { |r| r[:values].sum { |v| [ v, 0 ].max } }
    frame = chart_frame(totals, unit)
    n = rows.size
    slot = frame[:plot_w] / n.to_f
    bar_w = [ [ slot * 0.7, 3 ].max, 48 ].min
    parts = [ frame[:grid] ]
    rows.each_with_index do |row, i|
      x = frame[:left] + slot * i + (slot - bar_w) / 2
      acc = 0
      tip = ([ "#{row[:label]}（計 #{analytics_value(totals[i], unit)}）" ] +
             series.each_with_index.map { |s, si| "#{s[:label]}: #{analytics_value(row[:values][si], unit)}" }).join("\n")
      parts << %(<g class="viz-mark"><title>#{h(tip)}</title>)
      parts << %(<rect x="#{frame[:left] + slot * i}" y="#{frame[:top]}" width="#{slot}" height="#{frame[:plot_h]}" fill="transparent"/>)
      last_idx = row[:values].rindex { |v| v.positive? }
      row[:values].each_with_index do |v, si|
        next unless v.positive?
        y_top = frame[:y].call(acc + v)
        y_bot = frame[:y].call(acc)
        hgt = y_bot - y_top
        hgt -= 2 if hgt > 3 && si != last_idx # 系列間の 2px の隙間
        parts << if si == last_idx
          bar_path(x, y_top, bar_w, hgt, horizontal: false, negative: false, fill: series[si][:color])
        else
          %(<rect x="#{x.round(2)}" y="#{(y_top + (y_bot - y_top - hgt)).round(2)}" width="#{bar_w.round(2)}" height="#{hgt.round(2)}" fill="#{series[si][:color]}"/>)
        end
        acc += v
      end
      parts << "</g>"
    end
    parts << x_labels(rows.map { |r| r[:label] }, frame, slot)
    svg_wrap(frame[:width], frame[:height], parts.join, "積み上げ縦棒グラフ")
  end

  def stacked_horizontal(rows, series, unit)
    label_w = 210
    value_w = 96
    width = 820
    bar_area = width - label_w - value_w
    row_h = 26
    top = 6
    height = top + rows.size * row_h + 6
    totals = rows.map { |r| r[:values].sum { |v| [ v, 0 ].max } }
    max_v = totals.max.to_i.nonzero? || 1
    parts = []
    rows.each_with_index do |row, i|
      y = top + i * row_h
      tip = ([ "#{row[:label]}（計 #{analytics_value(totals[i], unit)}）" ] +
             series.each_with_index.map { |s, si| "#{s[:label]}: #{analytics_value(row[:values][si], unit)}" }).join("\n")
      parts << %(<g class="viz-mark"><title>#{h(tip)}</title>)
      parts << %(<rect x="0" y="#{y}" width="#{width}" height="#{row_h}" fill="transparent"/>)
      parts << %(<text x="#{label_w - 8}" y="#{y + 17}" text-anchor="end" class="viz-label">#{h(truncate(row[:label].to_s, length: 18))}</text>)
      acc = 0
      last_idx = row[:values].rindex { |v| v.positive? }
      row[:values].each_with_index do |v, si|
        next unless v.positive?
        x = label_w + bar_area * (acc.to_f / max_v)
        w = bar_area * (v.to_f / max_v)
        w -= 2 if w > 3 && si != last_idx
        parts << if si == last_idx
          bar_path(x, y + 5, w, row_h - 10, horizontal: true, negative: false, fill: series[si][:color])
        else
          %(<rect x="#{x.round(2)}" y="#{y + 5}" width="#{w.round(2)}" height="#{row_h - 10}" fill="#{series[si][:color]}"/>)
        end
        acc += v
      end
      parts << %(<text x="#{(label_w + bar_area * (acc.to_f / max_v) + 6).round(1)}" y="#{y + 17}" class="viz-value">#{h(analytics_value(totals[i], unit))}</text>)
      parts << "</g>"
    end
    parts << %(<line x1="#{label_w}" y1="#{top}" x2="#{label_w}" y2="#{height - 6}" stroke="#{AXIS_TEXT}" stroke-width="1"/>)
    svg_wrap(width, height, parts.join, "積み上げ横棒グラフ")
  end
end
