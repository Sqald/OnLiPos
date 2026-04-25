class Dashboard::BaseController < ApplicationController
  before_action :authenticate_user!
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found

  private

  def record_not_found
    redirect_to dashboard_root_path, alert: "指定されたリソースが見つかりません。"
  end
end