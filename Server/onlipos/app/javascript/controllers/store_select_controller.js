// 従業員フォームの「全店舗を選択」と所属店舗チェックボックスを連動させる。
// 対象は所属店舗のチェックボックス（store ターゲット）のみで、権限チェックボックスには触れない。
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["all", "store"]

  // 全店舗フラグがONなら、個別のチェックボックスも全てONにする（表示上の整合性）
  connect() {
    if (this.allTarget.checked) this.toggleAll()
  }

  // 「全店舗」クリック時: 個別の所属店舗をまとめて切り替える
  toggleAll() {
    this.storeTargets.forEach((cb) => { cb.checked = this.allTarget.checked })
  }

  // 個別が外されたら「全店舗」フラグも外す。
  // 個別を全て手動でONにしても意図的な「全店舗所属」とは限らないため、自動でONにはしない。
  toggleStore(event) {
    if (!event.target.checked) this.allTarget.checked = false
  }
}
