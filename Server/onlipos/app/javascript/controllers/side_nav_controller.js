// サイドメニュー: 開いたグループを覚え、キーワードで項目を絞り込む
import { Controller } from "@hotwired/stimulus"

const KEY = "onlipos.sideNav"

export default class extends Controller {
  static targets = ["query", "group", "item", "empty"]

  connect() {
    const saved = this.load()
    this.groupTargets.forEach((g) => {
      if (saved.includes(g.dataset.key)) g.open = true
      g.addEventListener("toggle", () => { if (!this.queryTarget.value) this.save() })
    })
    this.element.querySelector(".side-nav-link.active")?.scrollIntoView({ block: "nearest" })
  }

  filter() {
    const words = this.queryTarget.value.trim().toLowerCase().split(/\s+/).filter(Boolean)
    let hits = 0
    this.itemTargets.forEach((item) => {
      const match = words.every((w) => item.dataset.text.toLowerCase().includes(w))
      item.hidden = !match
      if (match) hits += 1
    })
    this.groupTargets.forEach((g) => {
      const any = [...g.querySelectorAll("li")].some((li) => !li.hidden)
      g.hidden = !any
      if (words.length) g.open = any
    })
    this.emptyTarget.hidden = hits > 0
  }

  load() {
    try { return JSON.parse(sessionStorage.getItem(KEY)) || [] } catch { return [] }
  }

  save() {
    try { sessionStorage.setItem(KEY, JSON.stringify(this.groupTargets.filter((g) => g.open).map((g) => g.dataset.key))) } catch { /* 保存できない環境では覚えない */ }
  }
}
