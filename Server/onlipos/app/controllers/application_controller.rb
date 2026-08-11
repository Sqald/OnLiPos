# 全コントローラ（管理者用を除く）の基底クラス。
# Devise 利用時に共通で必要となる許可パラメータの設定などを行う。
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  # Devise のストロングパラメータに、標準では許可されていない独自カラムを追加する
  def configure_permitted_parameters
    # 新規登録時 (sign_up) に許可するキーを追加
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :login_name, :user_type, :company_name, :last_name, :first_name ])
    # アカウント編集時 (account_update) に許可するキーを追加
    devise_parameter_sanitizer.permit(:account_update, keys: [ :login_name, :user_type, :company_name, :last_name, :first_name ])
  end
end
