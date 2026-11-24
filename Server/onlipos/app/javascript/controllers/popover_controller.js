// details を使ったメニューを、外側のクリックで閉じる
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  outside(event) {
    if (!this.element.contains(event.target)) this.element.open = false
  }
}
