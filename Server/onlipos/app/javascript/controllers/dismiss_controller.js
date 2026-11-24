// お知らせを閉じる
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  close() { this.element.remove() }
}
