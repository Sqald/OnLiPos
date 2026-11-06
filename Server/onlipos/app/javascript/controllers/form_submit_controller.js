// ボタン押下でフォームを通常送信する（インラインの onclick="this.form.submit()" の置き換え。CSP対応）。
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.form?.submit()
  }
}
