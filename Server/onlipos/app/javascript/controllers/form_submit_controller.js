// ボタン押下でフォームを送信する（バーコードリーダーの Enter では送信されないようにするため、送信ボタンを type="button" にした画面で使う）（インラインの onclick="this.form.submit()" の置き換え。CSP対応）。
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.form?.requestSubmit()
  }
}
