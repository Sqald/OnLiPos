// 一覧表をスマートフォンで読みやすくするため、各セルに見出しを付ける（CSS の data-label を使う）
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("table.data-table").forEach((table) => {
      const heads = [...table.querySelectorAll("thead th")].map((th) => th.textContent.trim())
      if (heads.length < 3 || table.classList.contains("an-table")) return
      table.classList.add("stackable")
      table.querySelectorAll("tbody tr").forEach((tr) => this.label(tr, heads))
    })
  }

  label(row, heads) {
    [...row.cells].forEach((td, i) => { if (!td.dataset.label && td.colSpan === 1) td.dataset.label = heads[i] || "" })
  }
}
