class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    # 新規登録時 (sign_up) に許可するキーを追加
    devise_parameter_sanitizer.permit(:sign_up, keys: [:login_name,:user_type, :company_name, :last_name, :first_name, :terms_of_service])
    # アカウント編集時 (account_update) に許可するキーを追加
    devise_parameter_sanitizer.permit(:account_update, keys: [:login_name, :user_type, :company_name, :last_name, :first_name])
  end
end
