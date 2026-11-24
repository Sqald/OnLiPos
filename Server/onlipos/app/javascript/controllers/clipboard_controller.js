// 値をコピーするボタン
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
      this.buttonTarget.textContent = "コピーしました"
    } catch {
      this.buttonTarget.textContent = "コピーできませんでした"
    }
    setTimeout(() => { this.buttonTarget.textContent = "コピー" }, 2000)
  }
}
