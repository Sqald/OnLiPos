// セット商品フォームの構成商品行を追加・削除する。
// 商品名はユーザー入力値のため innerHTML に埋め込まず、DOM API で安全に設定する（XSS対策）。
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body"]
  static values = { products: Array }

  add() {
    const tr = document.createElement("tr")
    tr.className = "bundle-item-row"

    const select = document.createElement("select")
    select.name = "items[][product_id]"
    select.className = "form-control"
    select.add(new Option("-- 商品を選択 --", ""))
    this.productsValue.forEach((p) => select.add(new Option(p.label, p.id)))

    const quantity = document.createElement("input")
    quantity.type = "number"
    quantity.name = "items[][quantity]"
    quantity.value = "1"
    quantity.min = "1"
    quantity.className = "form-control"
    quantity.style.textAlign = "right"

    const remove = document.createElement("button")
    remove.type = "button"
    remove.className = "btn-sm btn-danger"
    remove.textContent = "削除"
    remove.dataset.action = "bundle-items#remove"

    for (const child of [select, quantity, remove]) {
      const td = document.createElement("td")
      td.appendChild(child)
      tr.appendChild(td)
    }
    this.bodyTarget.appendChild(tr)
  }

  remove(event) {
    event.target.closest("tr")?.remove()
  }
}
