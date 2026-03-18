class Api::V1::PosDevicesController < Api::V1::BaseController 
  before_action :authenticate_pos_token, except: [:login]

  def login
    user = User.find_by(login_name: login_params[:userName])
    store = user&.stores&.find_by(ascii_name: login_params[:storeName])
    @pos_token = store&.pos_tokens&.find_by(ascii_name: login_params[:posName])

    if @pos_token&.authenticate(login_params[:password])
      @pos_token.regenerate_token
      @pos_token.update_columns(
        last_used_at: Time.current, 
        password_digest: nil
      )
      render :login, status: :ok
    else
      render json: { success: false, message: I18n.t('api.v1.pos_devices.login.failure') }, status: :ok
    end
  end

  def top_user_login
    # アクセス元のPOS端末が所属する店舗のオーナー配下の従業員から検索
    owner = @current_pos.store.user
    employee = owner.employees.find_by(code: user_login_params[:code])

    # 従業員が存在しない、またはPINが空の場合は即座に失敗させる
    if employee.nil? || user_login_params[:pin].blank?
      return render json: { success: false, message: I18n.t('api.v1.pos_devices.top_user_login.failure') }, status: :ok
    end

    # アカウントがロックされているか確認
    if employee.access_locked?
      return render json: { success: false, message: I18n.t('api.v1.pos_devices.top_user_login.locked') }, status: :ok
    end

    if employee.authenticate_pin(user_login_params[:pin])
      # 認証成功
      employee.unlock_access! # ロック情報をリセット
      
      # 全店舗権限があるか、または現在の店舗に所属しているか確認
      if employee.is_all_stores || employee.stores.exists?(@current_pos.store.id)
        render json: { success: true, employee_id: employee.id, employee_name: employee.name }
      else
        render json: { success: false, message: I18n.t('api.v1.pos_devices.top_user_login.not_authorized_for_store') }, status: :ok
      end
    else
      # 認証失敗
      employee.increment_failed_attempts # 失敗回数を記録
      render json: { success: false, message: I18n.t('api.v1.pos_devices.top_user_login.failure') }, status: :ok
    end
  end

  def check_operator
    # アクセス元のPOS端末が所属する店舗のオーナー配下の従業員から検索
    owner = @current_pos.store.user
    employee = owner.employees.find_by(code: user_login_params[:code])

    if employee
      render json: { success: true, name: employee.name }
    else
      render json: { success: false, message: I18n.t('api.v1.pos_devices.check_operator.failure', default: '担当者が見つかりません') }, status: :ok
    end
  end

  def provisioning
    # 現在のPOS端末に関連するプロビジョニングデータを取得
    # 優先順位: POS端末個別設定 > 店舗共通設定
    provisioning = @current_pos.provisioning
    provisioning ||= Provisioning.where(store: @current_pos.store).order(created_at: :desc).first

    if provisioning
      render json: {
        success: true,
        provisioning: {
          store_context: provisioning.store_context,
          hardware_settings: provisioning.hardware_settings
        }
      }, status: :ok
    else
      render json: { success: false, message: I18n.t('api.v1.pos_devices.provisioning.not_found', default: 'Provisioning data not found') }, status: :not_found
    end
  end

  def open
    # 従業員の特定
    owner = @current_pos.store.user
    employee = owner.employees.find_by(id: open_params[:employee_id])

    # 全店舗権限があるか、または現在の店舗に所属しているか確認
    unless employee && (employee.is_all_stores || employee.stores.exists?(@current_pos.store.id))
      return render json: { success: false, message: I18n.t('api.v1.pos_devices.open.employee_not_found') }, status: :ok
    end

    cash_data = open_params[:cash_drawer] || {}

    cash_log = CashLog.new(
      pos_token: @current_pos,
      employee: employee,
      open_date: open_params[:open_date],
      is_start: true,
      yen_10000: cash_data[:"10000"],
      yen_5000: cash_data[:"5000"],
      yen_1000: cash_data[:"1000"],
      yen_500: cash_data[:"500"],
      yen_100: cash_data[:"100"],
      yen_50: cash_data[:"50"],
      yen_10: cash_data[:"10"],
      yen_5: cash_data[:"5"],
      yen_1: cash_data[:"1"]
    )

    if cash_log.save
      render json: { success: true, message: I18n.t('api.v1.pos_devices.open.success') }, status: :ok
    else
      render json: { success: false, message: cash_log.errors.full_messages.join(", ") }, status: :ok
    end
  end

  # レジ金チェック（営業中のレジ残高確認）
  def cash_check
    previous_log, _opening_log, last_amount, expected_amount = cash_check_baseline

    cash_log = build_cash_log(is_start: false, is_end: false)
    return if performed?

    diff_amount = if expected_amount
                    cash_log.total_amount - expected_amount
                  end

    if cash_log.save
      render json: {
        success: true,
        message: I18n.t('api.v1.pos_devices.cash_check.success', default: 'レジ金チェックを登録しました'),
        last_amount: last_amount,
        expected_amount: expected_amount,
        actual_amount: cash_log.total_amount,
        diff_amount: diff_amount,
        last_logged_at: previous_log&.created_at
      }, status: :ok
    else
      render json: { success: false, message: cash_log.errors.full_messages.join(", ") }, status: :ok
    end
  end

  # レジ精算（営業終了時のレジ残高確定）
  def close_register
    previous_log, _opening_log, last_amount, expected_amount = cash_check_baseline
    cash_log = build_cash_log(is_start: false, is_end: true)
    return if performed?

    if cash_log.save
      diff_amount = if expected_amount
                      cash_log.total_amount - expected_amount
                    end

      render json: {
        success: true,
        message: I18n.t('api.v1.pos_devices.close_register.success', default: 'レジ精算を登録しました'),
        last_amount: last_amount,
        expected_amount: expected_amount,
        actual_amount: cash_log.total_amount,
        diff_amount: diff_amount,
        last_logged_at: previous_log&.created_at
      }, status: :ok
    else
      render json: { success: false, message: cash_log.errors.full_messages.join(", ") }, status: :ok
    end
  end

  # レジ金チェック画面用のコンテキスト（営業日トータル差異の基準）を返す。
  # 現在の営業日における開始時レジ金と、現時点までの現金売上から算出した
  # 「あるべきレジ金(expected_amount)」を返し、クライアント側はそれを基準に
  # 入力中も差異計算を行える。
  def cash_check_context
    previous_log, _opening_log, last_amount, expected_amount = cash_check_baseline

    render json: {
      success: true,
      last_amount: last_amount,
      expected_amount: expected_amount,
      last_logged_at: previous_log&.created_at
    }, status: :ok
  end

  private

  def login_params
    params.require(:pos).permit(:userName, :storeName, :posName, :password)
  end

  def user_login_params
    params.permit(:code, :pin)
  end

  def open_params
    params.permit(:employee_id, :open_date, :total_amount, 
      cash_drawer: [:"10000", :"5000", :"1000", :"500", :"100", :"50", :"10", :"5", :"1"]
    )
  end

  def cash_log_params
    params.permit(
      :employee_id,
      :total_amount,
      cash_drawer: [:"10000", :"5000", :"1000", :"500", :"100", :"50", :"10", :"5", :"1"]
    )
  end

  # 共通のレジ金ログ生成ロジック。
  # - POSトークン(@current_pos)と、そのオーナー配下の従業員のみを対象とし、
  #   他社・他店舗の従業員IDは通さないことで権限昇格を防ぎます。
  # - 合計金額はサーバー側で再計算し、クライアントからの total_amount をそのまま信用しないことで、
  #   改ざんされた値での記録を防ぎます。
  def build_cash_log(is_start:, is_end:)
    owner = @current_pos.store.user
    employee = owner.employees.find_by(id: cash_log_params[:employee_id])

    unless employee && (employee.is_all_stores || employee.stores.exists?(@current_pos.store.id))
      render json: { success: false, message: I18n.t('api.v1.pos_devices.open.employee_not_found') }, status: :ok
      return
    end

    cash_data = cash_log_params[:cash_drawer] || {}

    cash_log = CashLog.new(
      pos_token: @current_pos,
      employee: employee,
      open_date: Date.current,
      is_start: is_start,
      is_end: is_end,
      yen_10000: cash_data[:"10000"],
      yen_5000: cash_data[:"5000"],
      yen_1000: cash_data[:"1000"],
      yen_500: cash_data[:"500"],
      yen_100: cash_data[:"100"],
      yen_50: cash_data[:"50"],
      yen_10: cash_data[:"10"],
      yen_5: cash_data[:"5"],
      yen_1: cash_data[:"1"]
    )

    # クライアントから送られてきた合計金額とサーバー計算の結果が異なる場合はログだけ残す。
    # 今はビジネス的な許容としつつ、将来的にバリデーション強化ができるようにしておく。
    if cash_log_params[:total_amount].present?
      begin
        client_total = cash_log_params[:total_amount].to_i
        server_total = cash_log.total_amount
        if client_total != server_total
          Rails.logger.warn("[CashLog] total mismatch: client=#{client_total}, server=#{server_total}, pos_token=#{@current_pos.id}, employee=#{employee.id}")
        end
      rescue => e
        Rails.logger.warn("[CashLog] total check failed: #{e.class} - #{e.message}")
      end
    end

    cash_log
  end

  # 営業日トータル差異を計算するための基準情報を返す。
  # - 原則として当日の最初のレジ金ログ（開始レジ金）を基準とし、
  #   そこから現在までの現金売上合計を加算し、返品による返金額を減算した額を expected_amount とする。
  # - 当日分が存在しない場合は、従来通り直近のログを基準として扱う。
  def cash_check_baseline
    today_logs = @current_pos.cash_logs.where(open_date: Date.current).order(:created_at)
    # 「開始レジ金」は明示的に is_start を使う（チェック/精算が先に保存されても壊れないようにする）
    opening_log = today_logs.where(is_start: true).first
    # 「前回レジ金」は直近のログ（通常は直近のチェック、無ければ開始ログ）を返す
    previous_log = today_logs.last

    # 当日ログが無い場合は従来通り「直近のログ」を使う（過去営業日のデータでも動くようにする）。
    if previous_log.nil?
      previous_log = @current_pos.cash_logs.order(created_at: :desc).first
      return [previous_log, nil, nil, nil] unless previous_log

      cash_sales_sum = SalePayment.joins(:sale)
                                  .where(method: :cash)
                                  .where(sales: {
                                           user_id: @current_pos.store.user_id,
                                           store_id: @current_pos.store_id,
                                           pos_token_id: @current_pos.id
                                         })
                                  .where('sales.created_at > ?', previous_log.created_at)
                                  .sum(:amount)

      refund_cash_sum = Refund.joins(:sale)
                              .where(sales: {
                                       user_id: @current_pos.store.user_id,
                                       store_id: @current_pos.store_id,
                                       pos_token_id: @current_pos.id,
                                       payment_method: Sale.payment_methods[:cash]
                                     })
                              .where('refunds.created_at > ?', previous_log.created_at)
                              .sum(:total_amount)

      net_cash_sales = cash_sales_sum - refund_cash_sum

      last_amount = previous_log.total_amount
      expected_amount = last_amount + net_cash_sales
      [previous_log, nil, last_amount, expected_amount]
    else
      # 当日の開始ログがあれば、それを基準に expected_amount（あるべきレジ金）を算出する。
      baseline_log = opening_log || previous_log
      baseline_amount = baseline_log.total_amount

      cash_sales_sum = SalePayment.joins(:sale)
                                  .where(method: :cash)
                                  .where(sales: {
                                           user_id: @current_pos.store.user_id,
                                           store_id: @current_pos.store_id,
                                           pos_token_id: @current_pos.id
                                         })
                                  .where('sales.created_at > ?', baseline_log.created_at)
                                  .sum(:amount)

      refund_cash_sum = Refund.joins(:sale)
                              .where(sales: {
                                       user_id: @current_pos.store.user_id,
                                       store_id: @current_pos.store_id,
                                       pos_token_id: @current_pos.id,
                                       payment_method: Sale.payment_methods[:cash]
                                     })
                              .where('refunds.created_at > ?', baseline_log.created_at)
                              .sum(:total_amount)

      net_cash_sales = cash_sales_sum - refund_cash_sum

      expected_amount = baseline_amount + net_cash_sales
      last_amount = previous_log.total_amount
      [previous_log, opening_log, last_amount, expected_amount]
    end
  end
end
