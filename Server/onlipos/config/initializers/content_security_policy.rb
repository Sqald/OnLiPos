# Be sure to restart your server when you modify this file.

# アプリ全体の Content Security Policy。
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header
#
# - スクリプトは自ドメインのファイルと、nonce 付きの importmap タグのみ許可する
#   （画面ごとの処理は app/javascript/controllers の Stimulus コントローラに置き、
#   インラインの <script> / onclick 等は使わないこと）
# - スタイルはビュー内の style 属性を多用しているため 'unsafe-inline' を許可する
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.connect_src :self
    policy.font_src    :self, :data
    # トップページの Microsoft Store バッジ画像
    policy.img_src     :self, :data, "https://get.microsoft.com"
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.frame_ancestors :none
  end

  # importmap のインラインタグに付与する nonce。
  # Turbo Drive の画面遷移でも同じ値になるようセッションIDから生成する（Rails 標準の推奨設定）
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
