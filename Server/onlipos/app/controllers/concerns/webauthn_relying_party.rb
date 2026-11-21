# パスキー（WebAuthn）の Relying Party 設定。
# RP ID はアクセスされているホスト名、許可するオリジンは現在のURLと環境変数 HOST_NAME / HOST_PORT から組み立てる
# （nginx 経由で Host ヘッダーにポート番号が付かない構成でも検証できるようにするため）。
module WebauthnRelyingParty
  extend ActiveSupport::Concern

  private

  def webauthn_relying_party
    @webauthn_relying_party ||= WebAuthn::RelyingParty.new(
      id: request.host,
      name: "OnLiPos",
      allowed_origins: webauthn_allowed_origins
    )
  end

  def webauthn_allowed_origins
    origins = [ request.base_url ]
    host = ENV["HOST_NAME"].presence
    if host
      port = ENV["HOST_PORT"].presence
      origins << (port && port != "443" ? "https://#{host}:#{port}" : "https://#{host}")
    end
    origins.uniq
  end

  # fetch で送られた JSON 本文（パスキーの応答）をそのまま取り出す
  def webauthn_payload
    JSON.parse(request.raw_post)
  rescue JSON::ParserError
    {}
  end
end
