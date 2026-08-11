# POS端末（レジ本体）の認証・プロビジョニング・レジ開閉／点検／精算・レジ金入出金を扱うコントローラ。
# login のみ POS トークン未取得の状態で呼ばれるため認証を除外し、それ以外のアクションは
# BaseController の authenticate_pos_token で @current_pos がセットされている前提で動く。
class Api::V1::PosDevicesController < Api::V1::BaseController
  before_action :authenticate_pos_token, except: [ :login ]

  # POST /api/v1/pos_devices/login — POS端末そのもののログイン（ユーザー名・店舗名・POS名＋パスワード）。
  # 成功したらトークンを再発行し、以後のAPI呼び出しはそのトークンで認証する。
  def login
    brute_key = "pos_login:#{login_params[:userName]}:#{login_params[:storeName]}:#{login_params[:posName]}"
    if pos_login_locked?(brute_key)
      return render json: {
        success: false,
        message: "ログイン試行回数が上限に達しました。しばらく時間をおいてから再試行してください。"
      }, status: :too_many_requests
    end

    user = User.find_by(login_name: login_params[:userName])
    store = user&.stores&.find_by(ascii_name: login_params[:storeName])
    @pos_token = store&.pos_tokens&.find_by(ascii_name: login_params[:posName])

    if @pos_token&.authenticate(login_params[:password])
      reset_pos_login_failures(brute_key)
      @pos_token.regenerate_token
      @pos_token.update_columns(
        last_used_at: Time.current,
        password_digest: nil
      )
      render :login, status: :ok
    else
      increment_pos_login_failures(brute_key)
      render json: { success: false, message: I18n.t("api.v1.pos_devices.login.failure") }, status: :unauthorized
    end
  end

  # POST /api/v1/pos_devices/top_user_login — 従業員コード＋PINでのログイン（POS端末利用開始時）
  def top_user_login
    # アクセス元のPOS端末が所属する店舗のオーナー配下の従業員から検索
    owner = @current_pos.store.user
    employee = owner.employees.find_by(code: user_login_params[:code])

    # 従業員が存在しない、またはPINが空の場合は即座に失敗させる
    if employee.nil? || user_login_params[:pin].blank?
      return render json: { success: false, message: I18n.t("api.v1.pos_devices.top_user_login.failure") }, status: :unauthorized
    end

    # アカウントがロックされているか確認
    if employee.access_locked?
      return render json: { success: false, message: I18n.t("api.v1.pos_devices.top_user_login.locked") }, status: :forbidden
    end

    if employee.authenticate_pin(user_login_params[:pin])
      # 認証成功
      employee.unlock_access! # ロック情報をリセット

      # 全店舗権限があるか、または現在の店舗に所属しているか確認
      if employee.is_all_stores || employee.stores.exists?(@current_pos.store.id)
        render json: { success: true, employee_id: employee.id, employee_name: employee.name, permissions: employee.permission_keys }
      else
        render json: { success: false, message: I18n.t("api.v1.pos_devices.top_user_login.not_authorized_for_store") }, status: :forbidden
      end
    else
      # 認証失敗
      employee.increment_failed_attempts # 失敗回数を記録
      render json: { success: false, message: I18n.t("api.v1.pos_devices.top_user_login.failure") }, status: :unauthorized
    end
  end

  # 業務中（返品・在庫入出庫等）の担当者PIN認証。
  # top_user_login と同様にPINを検証するが、「ログイン」ではなく「中間承認」用途。
  def verify_employee
    owner = @current_pos.store.user
    employee = owner.employees.find_by(code: user_login_params[:code])

    if employee.nil? || user_login_params[:pin].blank?
      return render json: { success: false, message: I18n.t("api.v1.pos_devices.check_operator.failure", default: "担当者が見つかりません") }, status: :unauthorized
    end

    if employee.access_locked?
      return render json: { success: false, message: I18n.t("api.v1.pos_devices.top_user_login.locked", default: "アカウントがロックされています") }, status: :forbidden
    end

    if employee.authenticate_pin(user_login_params[:pin])
      employee.unlock_access!
      if employee.is_all_stores || employee.stores.exists?(@current_pos.store.id)
        render json: { success: true, employee_id: employee.id, employee_name: employee.name, permissions: employee.permission_keys }
      else
        render json: { success: false, message: I18n.t("api.v1.pos_devices.top_user_login.not_authorized_for_store", default: "店舗権限がありません") }, status: :forbidden
      end
    else
      employee.increment_failed_attempts
      render json: { success: false, message: I18n.t("api.v1.pos_devices.top_user_login.failure", default: "PINが正しくありません") }, status: :unauthorized
    end
  end

  # POST /api/v1/pos_devices/check_operator — 従業員コードのみで担当者情報を取得（PIN不要の簡易確認）
  def check_operator
    # アクセス元のPOS端末が所属する店舗のオーナー配下の従業員から検索
    owner = @current_pos.store.user
    employee = owner.employees.find_by(code: user_login_params[:code])

    if employee
      render json: { success: true, name: employee.name, employee_id: employee.id, permissions: employee.permission_keys }
    else
      render json: { success: false, message: I18n.t("api.v1.pos_devices.check_operator.failure", default: "担当者が見つかりません") }, status: :not_found
    end
  end

  # POST /api/v1/pos_devices/provisioning — この端末向けのプロビジョニング設定を取得
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
      render json: { success: false, message: I18n.t("api.v1.pos_devices.provisioning.not_found", default: "Provisioning data not found") }, status: :not_found
    end
  end

  # POST /api/v1/pos_devices/open — レジ開設（開始時の金種実査を記録し、新しいレジセッション(Z)を開く）
  def open
    # 従業員の特定
    owner = @current_pos.store.user
    employee = owner.employees.find_by(id: open_params[:employee_id])

    # 全店舗権限があるか、または現在の店舗に所属しているか確認
    unless employee && (employee.is_all_stores || employee.stores.exists?(@current_pos.store.id))
      return render json: { success: false, message: I18n.t("api.v1.pos_devices.open.employee_not_found") }, status: :forbidden
    end

    # 前回の精算が済んでいない（開いたままの）セッションがあれば開設不可
    if current_open_session
      return render json: {
        success: false,
        message: "前回のレジ精算が完了していません。先に精算（レジ締め）を実行してください"
      }, status: :unprocessable_entity
    end

    # 開設時の金種内訳から実査レコードを組み立てる
    cash_data = open_params[:cash_drawer] || {}

    cash_log = CashLog.new(
      pos_token: @current_pos,
      employee: employee,
      open_date: open_params[:open_date],
      is_start: true,
      log_type: :open,
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

    unless cash_log.valid?
      return render json: { success: false, message: cash_log.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    # 営業日はクライアント指定を優先し、不正な形式なら当日にフォールバックする
    business_date =
      begin
        open_params[:open_date].present? ? Date.parse(open_params[:open_date].to_s) : Date.current
      rescue ArgumentError
        Date.current
      end

    session = nil
    # レジセッション作成・実査保存・ジャーナル記録をまとめて1トランザクションで行う
    ActiveRecord::Base.transaction do
      # Zカウンタの採番は pos_token 行ロックで直列化する（レシート連番と同方式）
      @current_pos.with_lock do
        z_number = (@current_pos.register_sessions.maximum(:z_number) || 0) + 1
        session = @current_pos.register_sessions.create!(
          user: owner,
          store: @current_pos.store,
          business_date: business_date,
          z_number: z_number,
          status: :open,
          opened_at: Time.current,
          opening_employee: employee,
          opening_float: cash_log.total_amount
        )
      end

      cash_log.register_session = session
      cash_log.save!
      JournalEntry.create_from_cash_log!(cash_log, :register_open)
    end

    render json: {
      success: true,
      message: I18n.t("api.v1.pos_devices.open.success"),
      register_session: {
        id: session.id,
        z_number: session.z_number,
        business_date: session.business_date.to_s,
        opening_float: session.opening_float
      }
    }, status: :ok
  rescue ActiveRecord::RecordNotUnique
    # 部分一意インデックス（1端末1openセッション）による同時開設の競合
    render json: { success: false, message: "レジ開設が重複しました。既に開設済みです" }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  end

  # レジ金チェック（営業中のレジ残高確認）
  def cash_check
    # 基準情報（前回ログ・あるべきレジ金）を取得し、今回の実査ログを組み立てる
    previous_log, _opening_log, last_amount, expected_amount = cash_check_baseline

    cash_log = build_cash_log(is_start: false, is_end: false)
    return if performed?

    diff_amount = if expected_amount
                    cash_log.total_amount - expected_amount
    end

    # 実査時点の理論在高と過不足を確定保存する（後から検証できるようにする）
    cash_log.log_type = :check
    cash_log.register_session = current_open_session
    cash_log.expected_amount = expected_amount
    cash_log.diff_amount = diff_amount

    saved = false
    ActiveRecord::Base.transaction do
      if cash_log.save
        JournalEntry.create_from_cash_log!(cash_log, :cash_check)
        saved = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if saved
      render json: {
        success: true,
        message: I18n.t("api.v1.pos_devices.cash_check.success", default: "レジ金チェックを登録しました"),
        last_amount: last_amount,
        expected_amount: expected_amount,
        actual_amount: cash_log.total_amount,
        diff_amount: diff_amount,
        last_logged_at: previous_log&.created_at
      }, status: :ok
    else
      render json: { success: false, message: cash_log.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  # レジ金途中回収。cash_pickup 権限を持つ従業員のみ実行可。
  def cash_pickup
    owner = @current_pos.store.user
    employee = owner.employees.find_by(id: pickup_params[:employee_id])

    unless employee && (employee.is_all_stores || employee.stores.exists?(@current_pos.store.id))
      return render json: { success: false, message: "担当者が見つかりません" }, status: :forbidden
    end

    unless employee.permitted?("cash_pickup")
      return render json: { success: false, message: "途中回収の権限がありません" }, status: :forbidden
    end

    amount = pickup_params[:amount].to_i
    if amount <= 0
      return render json: { success: false, message: "回収金額は1円以上を指定してください" }, status: :unprocessable_entity
    end

    cash_log = CashLog.new(
      pos_token: @current_pos,
      employee: employee,
      open_date: Date.current,
      is_start: false,
      is_end: false,
      is_pickup: true,
      log_type: :pickup,
      register_session: current_open_session,
      pickup_amount: amount,
      pickup_reason: pickup_params[:reason],
      yen_10000: 0, yen_5000: 0, yen_1000: 0, yen_500: 0, yen_100: 0,
      yen_50: 0, yen_10: 0, yen_5: 0, yen_1: 0
    )

    saved = false
    ActiveRecord::Base.transaction do
      if cash_log.save
        JournalEntry.create_from_cash_log!(cash_log, :cash_pickup)
        saved = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if saved
      render json: {
        success: true,
        pickup_id: cash_log.id,
        pickup_amount: amount,
        pickup_reason: cash_log.pickup_reason,
        created_at: cash_log.created_at
      }, status: :ok
    else
      render json: { success: false, message: cash_log.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  # レジ精算（営業終了時のレジ残高確定）
  # セッションが開いている場合はスナップショットを確定保存して close する（Z締め）。
  def close_register
    session = current_open_session
    previous_log, _opening_log, last_amount, expected_amount = cash_check_baseline
    cash_log = build_cash_log(is_start: false, is_end: true)
    return if performed?

    # 実査結果と理論在高の過不足を確定する
    diff_amount = expected_amount ? cash_log.total_amount - expected_amount : nil
    cash_log.log_type = :close
    cash_log.register_session = session
    cash_log.expected_amount = expected_amount
    cash_log.diff_amount = diff_amount

    session_summary = nil
    # 実査保存・セッションのclose・ジャーナル記録をまとめて1トランザクションで行う
    ActiveRecord::Base.transaction do
      cash_log.save!

      if session
        totals = session.current_totals
        session.update!(
          status: :closed,
          closed_at: Time.current,
          closing_employee_id: cash_log.employee_id,
          closing_counted_amount: cash_log.total_amount,
          expected_cash_amount: expected_amount,
          cash_diff_amount: diff_amount,
          next_opening_float: next_opening_float_param,
          closing_summary: session.report_breakdown,
          **totals
        )
        session_summary = {
          id: session.id,
          z_number: session.z_number,
          business_date: session.business_date.to_s,
          opening_float: session.opening_float,
          next_opening_float: session.next_opening_float
        }.merge(totals)
      end

      JournalEntry.create_from_cash_log!(cash_log, :register_close)
    end

    render json: {
      success: true,
      message: I18n.t("api.v1.pos_devices.close_register.success", default: "レジ精算を登録しました"),
      last_amount: last_amount,
      expected_amount: expected_amount,
      actual_amount: cash_log.total_amount,
      diff_amount: diff_amount,
      last_logged_at: previous_log&.created_at,
      register_session: session_summary
    }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, message: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
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

  # 点検（X）/ 精算（Z）レポートの集計データを返す。
  # - z_number 指定なし: 現在の open セッションの点検レポート（営業中何度でも）
  # - z_number 指定あり: 精算済みセッションのスナップショット（Zレポート再印字）
  def register_report
    # 権限チェック用に担当者を特定
    owner = @current_pos.store.user
    employee = owner.employees.find_by(id: params[:employee_id])

    unless employee && (employee.is_all_stores || employee.stores.exists?(@current_pos.store.id))
      return render json: { success: false, message: I18n.t("api.v1.pos_devices.open.employee_not_found") }, status: :forbidden
    end

    unless employee.permitted?("cash_check")
      return render json: { success: false, message: "点検・精算レポートの権限がありません" }, status: :forbidden
    end

    if params[:z_number].present?
      session = @current_pos.register_sessions.closed.find_by(z_number: params[:z_number])
      unless session
        return render json: { success: false, message: "指定された精算が見つかりません" }, status: :not_found
      end
      render json: z_report_json(session), status: :ok
    else
      session = current_open_session
      unless session
        return render json: { success: false, message: "レジが開設されていません" }, status: :unprocessable_entity
      end
      render json: x_report_json(session), status: :ok
    end
  end

  private

  # ブルートフォース対策: 同一ユーザー/店舗/POS名の組み合わせで失敗回数が上限（10回）に達したか
  def pos_login_locked?(key)
    (Rails.cache.read("#{key}:count") || 0) >= 10
  end

  # ログイン失敗回数をキャッシュに記録（1時間で自動失効）
  def increment_pos_login_failures(key)
    count = (Rails.cache.read("#{key}:count") || 0) + 1
    Rails.cache.write("#{key}:count", count, expires_in: 1.hour)
  end

  # ログイン成功時に失敗カウンタをリセットする
  def reset_pos_login_failures(key)
    Rails.cache.delete("#{key}:count")
  end

  def login_params
    params.require(:pos).permit(:userName, :storeName, :posName, :password)
  end

  def user_login_params
    params.permit(:code, :pin)
  end

  def open_params
    params.permit(:employee_id, :open_date, :total_amount,
      cash_drawer: [ :"10000", :"5000", :"1000", :"500", :"100", :"50", :"10", :"5", :"1" ]
    )
  end

  def cash_log_params
    params.permit(
      :employee_id,
      :total_amount,
      :next_opening_float,
      cash_drawer: [ :"10000", :"5000", :"1000", :"500", :"100", :"50", :"10", :"5", :"1" ]
    )
  end

  # 現在開いているレジセッション（なければ nil = レガシー動作）
  def current_open_session
    return @current_open_session if defined?(@current_open_session)
    @current_open_session = @current_pos.register_sessions.open.first
  end

  # レポート（X/Z）に共通するレジセッションのヘッダー情報
  def session_header(session)
    {
      id: session.id,
      z_number: session.z_number,
      business_date: session.business_date.to_s,
      status: session.status,
      opened_at: session.opened_at,
      closed_at: session.closed_at,
      opening_float: session.opening_float,
      opening_employee_name: session.opening_employee&.name,
      closing_employee_name: session.closing_employee&.name,
      store_name: session.store.name,
      pos_name: session.pos_token.name
    }
  end

  # 点検レポート（X）: 現時点の集計をその場で計算する
  def x_report_json(session)
    totals = session.current_totals
    {
      success: true,
      report_type: "x",
      register_session: session_header(session),
      totals: totals,
      expected_cash_amount: session.expected_cash_now(totals),
      breakdown: session.report_breakdown,
      generated_at: Time.current
    }
  end

  # 精算レポート（Z）: 精算時に確定保存したスナップショットをそのまま返す
  def z_report_json(session)
    {
      success: true,
      report_type: "z",
      register_session: session_header(session),
      totals: {
        sales_count: session.sales_count,
        sales_total: session.sales_total,
        refund_count: session.refund_count,
        refund_total: session.refund_total,
        void_count: session.void_count,
        void_total: session.void_total,
        discount_total: session.discount_total,
        cash_sales_total: session.cash_sales_total,
        cash_refund_total: session.cash_refund_total,
        cash_in_total: session.cash_in_total,
        cash_out_total: session.cash_out_total
      },
      expected_cash_amount: session.expected_cash_amount,
      closing_counted_amount: session.closing_counted_amount,
      cash_diff_amount: session.cash_diff_amount,
      next_opening_float: session.next_opening_float,
      breakdown: session.closing_summary,
      generated_at: Time.current
    }
  end

  # 精算時に指定される翌営業日の釣銭準備金（任意）
  def next_opening_float_param
    value = cash_log_params[:next_opening_float]
    value.present? ? value.to_i : nil
  end

  # cash_pickup アクション用のストロングパラメータ
  def pickup_params
    params.permit(:employee_id, :amount, :reason)
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
      render json: { success: false, message: I18n.t("api.v1.pos_devices.open.employee_not_found") }, status: :forbidden
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
  # - レジセッションが開いている場合はセッション基準（釣銭準備金 + セッション中の現金増減）。
  # - セッションがない場合（レガシー期間・旧クライアント）は従来の created_at 期間推測で計算する。
  def cash_check_baseline
    return session_baseline(current_open_session) if current_open_session

    today_logs = @current_pos.cash_logs.where(open_date: Date.current).order(:created_at)
    # 「開始レジ金」は明示的に is_start を使う（チェック/精算が先に保存されても壊れないようにする）
    opening_log = today_logs.where(is_start: true).first
    # 「前回レジ金」は直近のログ（通常は直近のチェック、無ければ開始ログ）を返す
    previous_log = today_logs.last

    # 当日ログが無い場合は従来通り「直近のログ」を使う（過去営業日のデータでも動くようにする）。
    if previous_log.nil?
      previous_log = @current_pos.cash_logs.order(created_at: :desc).first
      return [ previous_log, nil, nil, nil ] unless previous_log

      cash_sales_sum = cash_sales_since(previous_log.created_at)
      refund_cash_sum = refund_cash_since(previous_log.created_at)
      pickup_sum = pickup_sum_since(previous_log.created_at)
      net_cash_sales = cash_sales_sum - refund_cash_sum

      last_amount = previous_log.total_amount
      expected_amount = last_amount + net_cash_sales - pickup_sum
      [ previous_log, nil, last_amount, expected_amount ]
    else
      # 当日の開始ログがあれば、それを基準に expected_amount（あるべきレジ金）を算出する。
      baseline_log = opening_log || previous_log
      baseline_amount = baseline_log.total_amount

      cash_sales_sum = cash_sales_since(baseline_log.created_at)
      refund_cash_sum = refund_cash_since(baseline_log.created_at)
      pickup_sum = pickup_sum_since(baseline_log.created_at)
      net_cash_sales = cash_sales_sum - refund_cash_sum

      expected_amount = baseline_amount + net_cash_sales - pickup_sum
      last_amount = previous_log.total_amount
      [ previous_log, opening_log, last_amount, expected_amount ]
    end
  end

  # セッション基準の理論在高。セッションに紐付く売上・返品・入出金だけで閉じるため、
  # 深夜営業・締め忘れ・同日複数回精算でも壊れない。
  def session_baseline(session)
    logs = session.cash_logs.where.not(log_type: :pickup).order(:created_at)
    previous_log = logs.last
    opening_log  = logs.detect(&:log_open?)

    expected_amount = session.expected_cash_now
    last_amount = previous_log&.total_amount

    [ previous_log, opening_log, last_amount, expected_amount ]
  end

  # 指定日時以降のこのPOSの現金売上合計（sale_payments.method=cash ベースで正確に集計）
  def cash_sales_since(since)
    SalePayment.joins(:sale)
               .where(method: :cash)
               .where(sales: {
                        user_id: @current_pos.store.user_id,
                        store_id: @current_pos.store_id,
                        pos_token_id: @current_pos.id,
                        status: Sale.statuses[:completed]
                      })
               .where("sales.created_at > ?", since)
               .sum(:amount)
  end

  # 指定日時以降のこのPOSの途中回収合計
  def pickup_sum_since(since)
    @current_pos.cash_logs
                .where(is_pickup: true)
                .where("created_at > ?", since)
                .sum(:pickup_amount)
                .to_i
  end

  # 指定日時以降のこのPOSの現金返金合計。
  # sale.payment_method（主たる支払い方法）ではなく、元売上の実際の現金支払い比率で按分する。
  # 按分式: refund.total_amount × (元売上の現金支払い額 / 元売上合計)
  def refund_cash_since(since)
    Refund
      .joins(:sale)
      .joins(
        "LEFT JOIN (
          SELECT sale_id, SUM(amount) AS cash_amount
          FROM sale_payments
          WHERE method = 0
          GROUP BY sale_id
        ) AS cash_sums ON cash_sums.sale_id = sales.id"
      )
      .where(sales: {
               user_id: @current_pos.store.user_id,
               store_id: @current_pos.store_id,
               pos_token_id: @current_pos.id
             })
      .where("refunds.created_at > ?", since)
      .where("sales.total_amount > 0")
      .sum("ROUND(refunds.total_amount::numeric * COALESCE(cash_sums.cash_amount, 0) / sales.total_amount)")
      .to_i
  end
end
