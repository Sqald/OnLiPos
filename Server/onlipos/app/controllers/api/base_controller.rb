# すべての API コントローラ（api/v1 以下）の共通ルート。
# ActionController::API を継承し、ビュー描画やセッション等の機能を持たないAPI専用の基底クラス。
class Api::BaseController < ActionController::API
end
