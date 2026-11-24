// ダッシュボードの枠: スマートフォンでサイドメニューを開閉する
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "sidebar"]

  toggle() {
    this.setOpen(!document.body.classList.contains("nav-open"))
  }

  close() {
    if (document.body.classList.contains("nav-open")) this.setOpen(false)
  }

  setOpen(open) {
    document.body.classList.toggle("nav-open", open)
    this.toggleTargets.forEach((t) => t.setAttribute("aria-expanded", open))
    if (open) this.sidebarTarget.querySelector("a, summary")?.focus()
  }
}
