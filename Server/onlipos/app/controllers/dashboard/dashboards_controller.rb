# ダッシュボードのトップページ（ホーム画面）を担当するコントローラ。
# ログインユーザーが保有する店舗・POS端末の概要を表示する。
class Dashboard::DashboardsController < Dashboard::BaseController
  # トップ画面に表示する店舗一覧・全POS端末一覧を取得する
  def index
    @stores = current_user.stores.includes(:pos_tokens)
    @all_pos_tokens = @stores.map(&:pos_tokens).flatten
  end
end
