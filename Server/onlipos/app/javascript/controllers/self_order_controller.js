// セルフ注文: 数量の増減と、合計点数・金額の表示
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "count", "total", "submit"]

  connect() { this.update() }

  plus(event) { this.step(event, 1) }

  minus(event) { this.step(event, -1) }

  step(event, delta) {
    const input = event.currentTarget.parentElement.querySelector("input")
    const max = Number(input.max) || 99
    input.value = Math.min(max, Math.max(0, (Number(input.value) || 0) + delta))
    this.update()
  }

  update() {
    let count = 0
    let total = 0
    this.itemTargets.forEach((item) => {
      const quantity = Number(item.querySelector("input[type=number]").value) || 0
      const options = [...item.querySelectorAll("input[type=checkbox]:checked")].reduce((sum, o) => sum + Number(o.dataset.price || 0), 0)
      count += quantity
      total += quantity * (Number(item.dataset.price) + options)
      item.classList.toggle("selected", quantity > 0)
    })
    this.countTarget.textContent = count
    this.totalTarget.textContent = `¥${total.toLocaleString("ja-JP")}`
    this.submitTarget.disabled = count === 0
  }
}
