// パスキー（WebAuthn）の登録・認証。サーバーからチャレンジ（options）を受け取り、
// ブラウザの navigator.credentials API で署名した結果をサーバーへ送って検証してもらう。
//   data-passkey-mode-value     : "register"（登録）/ "authenticate"（ログイン時の確認）
//   data-passkey-options-url-value / data-passkey-verify-url-value : サーバーのエンドポイント
import { Controller } from "@hotwired/stimulus"

const toBuffer = (value) => {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/")
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4)
  const binary = atob(padded)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes.buffer
}

const toBase64url = (buffer) => {
  const bytes = new Uint8Array(buffer)
  let binary = ""
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i])
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
}

// PublicKeyCredential をサーバーが受け取れる JSON 形式に変換する
const serialize = (credential) => {
  const response = credential.response
  const json = {
    id: credential.id,
    rawId: toBase64url(credential.rawId),
    type: credential.type,
    authenticatorAttachment: credential.authenticatorAttachment ?? null,
    clientExtensionResults: credential.getClientExtensionResults ? credential.getClientExtensionResults() : {},
    response: { clientDataJSON: toBase64url(response.clientDataJSON) }
  }
  if (response.attestationObject) {
    json.response.attestationObject = toBase64url(response.attestationObject)
    json.response.transports = response.getTransports ? response.getTransports() : []
  }
  if (response.authenticatorData) {
    json.response.authenticatorData = toBase64url(response.authenticatorData)
    json.response.signature = toBase64url(response.signature)
    json.response.userHandle = response.userHandle ? toBase64url(response.userHandle) : null
  }
  return json
}

export default class extends Controller {
  static targets = ["nickname", "error", "button"]
  static values = { mode: String, optionsUrl: String, verifyUrl: String }

  connect() {
    if (!window.PublicKeyCredential) {
      this.showError("このブラウザはパスキーに対応していません。認証アプリをご利用ください。")
      if (this.hasButtonTarget) this.buttonTarget.disabled = true
    }
  }

  async start(event) {
    event.preventDefault()
    this.showError("")
    this.setBusy(true)
    try {
      const options = await this.post(this.optionsUrlValue, {})
      const credential = this.modeValue === "register" ? await this.create(options) : await this.get(options)
      const body = { credential: serialize(credential) }
      if (this.hasNicknameTarget) body.nickname = this.nicknameTarget.value
      const result = await this.post(this.verifyUrlValue, body)
      window.location.assign(result.redirect)
    } catch (error) {
      if (error.redirect) { window.location.assign(error.redirect); return }
      this.showError(this.messageFor(error))
      this.setBusy(false)
    }
  }

  create(options) {
    const publicKey = { ...options, challenge: toBuffer(options.challenge), user: { ...options.user, id: toBuffer(options.user.id) } }
    publicKey.excludeCredentials = (options.excludeCredentials || []).map((c) => ({ ...c, id: toBuffer(c.id) }))
    return navigator.credentials.create({ publicKey })
  }

  get(options) {
    const publicKey = { ...options, challenge: toBuffer(options.challenge) }
    publicKey.allowCredentials = (options.allowCredentials || []).map((c) => ({ ...c, id: toBuffer(c.id) }))
    return navigator.credentials.get({ publicKey })
  }

  async post(url, body) {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify(body)
    })
    const json = await response.json().catch(() => ({}))
    if (!response.ok) {
      const error = new Error(json.error || "通信に失敗しました。")
      error.redirect = json.redirect
      throw error
    }
    return json
  }

  // ブラウザの例外（英語）を利用者向けのメッセージに置き換える
  messageFor(error) {
    switch (error.name) {
      case "NotAllowedError":
      case "AbortError":
        return "パスキーの操作がキャンセルされたか、時間切れになりました。"
      case "InvalidStateError":
        return "この端末のパスキーはすでに登録されています。"
      case "SecurityError":
        return "このアドレスではパスキーを使えません（HTTPSでアクセスしているか確認してください）。"
      case "NotSupportedError":
        return "この端末・ブラウザはパスキーに対応していません。認証アプリをご利用ください。"
      default:
        return error.message || "パスキーの処理に失敗しました。"
    }
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.hidden = message === ""
  }

  setBusy(busy) {
    if (this.hasButtonTarget) this.buttonTarget.disabled = busy
  }
}
