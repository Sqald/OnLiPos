// Stimulusの動作確認用サンプルコントローラ。
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // 要素がDOMに接続された際にテキストを書き換える。
  connect() {
    this.element.textContent = "Hello World!"
  }
}
