# Web ダッシュボード配下の全コントローラの基底クラス。
# Devise によるセッション認証を必須化し、レコード未検出時の共通ハンドリングを提供する。
class Dashboard::BaseController < ApplicationController
  before_action :authenticate_user!
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

  # 対象レコードが見つからない場合はダッシュボードトップへ戻す
  def record_not_found
    redirect_to dashboard_root_path, alert: "指定されたリソースが見つかりません。"
  end
end
