# 画面で使うアイコン（24x24 の線画 SVG）。外部フォントや画像を読み込まずに表示する。
module IconHelper
  ICONS = {
    home: "M3 11l9-8 9 8M5 9.5V21h5v-6h4v6h5V9.5",
    chart: "M4 20V4M4 20h16M8 16v-5M12 16V8M16 16v-7",
    receipt: "M6 3h12v18l-3-2-3 2-3-2-3 2zM9 8h6M9 12h6",
    register: "M4 10h16v10H4zM7 10V5h10v5M8 14h2M12 14h2M16 14h0M8 17h8",
    tag: "M3 12V4h8l10 10-8 8zM7.5 8.5h.01",
    gift: "M4 11h16v10H4zM3 7h18v4H3zM12 7v14M12 7c-2-4-6-4-6-1 0 1 1 1 6 1zM12 7c2-4 6-4 6-1 0 1-1 1-6 1z",
    box: "M3 8l9-5 9 5v9l-9 5-9-5zM3 8l9 5 9-5M12 13v9",
    store: "M4 10v10h16V10M3 10l2-6h14l2 6c0 3-4 3-4.500 0-.5 3-4 3-4.500 0-.5 3-4 3-4.500 0C7 13 3 13 3 10zM10 20v-5h4v5",
    plug: "M9 3v5M15 3v5M6 8h12v3a6 6 0 01-12 0zM12 17v4",
    gear: "M12 9a3 3 0 100 6 3 3 0 000-6zM12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M19 5l-2 2M7 17l-2 2",
    help: "M12 3a9 9 0 100 18 9 9 0 000-18zM9.500 9.500a2.500 2.500 0 115 0c0 1.500-2.500 2-2.500 3.500M12 17h.01",
    user: "M12 4a4 4 0 100 8 4 4 0 000-8zM4 21c0-4 4-6 8-6s8 2 8 6",
    menu: "M4 6h16M4 12h16M4 18h16",
    close: "M6 6l12 12M18 6L6 18",
    search: "M11 4a7 7 0 100 14 7 7 0 000-14zM16 16l5 5",
    plus: "M12 5v14M5 12h14",
    back: "M15 5l-7 7 7 7",
    next: "M9 5l7 7-7 7",
    down: "M6 9l6 6 6-6",
    download: "M12 4v11M7 11l5 5 5-5M5 20h14",
    alert: "M12 3l10 18H2zM12 10v5M12 18h.01",
    check: "M5 13l4 4L19 7",
    info: "M12 3a9 9 0 100 18 9 9 0 000-18zM12 11v6M12 7.500h.01",
    people: "M9 5a3.500 3.500 0 100 7 3.500 3.500 0 000-7zM2 20c0-4 3.500-5.500 7-5.500s7 1.500 7 5.500M16 5.500a3 3 0 010 6M18 15c2.500.5 4 2 4 5",
    tablet: "M5 3h14v18H5zM11 18h2",
    logout: "M14 4h5v16h-5M10 8l-4 4 4 4M6 12h9",
    calendar: "M4 6h16v15H4zM4 10h16M8 3v5M16 3v5",
    shield: "M12 3l8 3v6c0 5-4 8-8 9-4-1-8-4-8-9V6z"
  }.freeze

  def icon(name, size: 20, **options)
    css = [ "icon", options[:class] ].compact.join(" ")
    content_tag(:svg, tag.path(d: ICONS.fetch(name)), class: css, width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
                "stroke-width": 1.8, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": true)
  end
end
