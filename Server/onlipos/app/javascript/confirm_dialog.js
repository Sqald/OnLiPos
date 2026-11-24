// turbo_confirm の確認を、ブラウザ標準の小さなダイアログではなく見やすい画面内ダイアログで表示する。
// dialog が無いページ・未対応のブラウザでは標準の確認を使う。
import { Turbo } from "@hotwired/turbo-rails"

const DESTRUCTIVE = /削除|取り消|取消|停止|解除|リセット|無効|中止|退会|作り直|使えなく/

Turbo.config.forms.confirm = (message) => {
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog || typeof dialog.showModal !== "function") return Promise.resolve(window.confirm(message))

  const ok = dialog.querySelector("[data-confirm-ok]")
  dialog.querySelector(".confirm-message").textContent = message
  ok.classList.toggle("btn-danger", DESTRUCTIVE.test(message))
  dialog.returnValue = "cancel"
  dialog.showModal()
  return new Promise((resolve) => {
    dialog.addEventListener("close", () => resolve(dialog.returnValue === "confirm"), { once: true })
  })
}
