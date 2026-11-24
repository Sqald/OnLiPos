# 2段階認証の画面用ヘルパー
module MfaHelper
  # 認証アプリ登録用の QR コード（otpauth:// URI を SVG にし、data: URI の画像として埋め込む）
  def mfa_qr_svg(uri, alt: "認証アプリ登録用QRコード")
    svg = RQRCode::QRCode.new(uri).as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true)
    image_tag("data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}", class: "mfa-qr-svg", alt: alt)
  end

  # 手入力用に秘密鍵を4文字ずつ区切って表示する
  def mfa_secret_display(secret)
    secret.to_s.scan(/.{1,4}/).join(" ")
  end
end
