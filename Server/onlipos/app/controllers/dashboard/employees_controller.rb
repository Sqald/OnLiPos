# 従業員（POSレジ操作者）の管理画面。従業員の登録・編集・削除と、
# 店舗への紐付け・権限（PERMISSION_CATALOG）の設定を扱う。
class Dashboard::EmployeesController < Dashboard::BaseController
  before_action :set_employee, only: [ :edit, :update, :destroy ]
  before_action :set_stores, only: [ :new, :create, :edit, :update ]

  # 自ユーザー配下の従業員一覧
  def index
    @employees = current_user.employees
  end

  # 新規登録フォーム
  def new
    @employee = current_user.employees.build
  end

  # 従業員を登録し、権限（チェックボックス選択分）を同期する
  def create
    @employee = current_user.employees.build(employee_params)
    if @employee.save
      @employee.sync_permissions(permission_params)
      redirect_to dashboard_employees_path, notice: "従業員を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # 編集フォーム（before_actionでセット済みの@employeeを表示）
  def edit
  end

  # 従業員情報を更新し、権限を同期する
  def update
    if @employee.update(employee_params)
      @employee.sync_permissions(permission_params)
      redirect_to dashboard_employees_path, notice: "従業員情報を更新しました。"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 従業員を削除する
  def destroy
    @employee.destroy
    redirect_to dashboard_employees_path, notice: "従業員を削除しました。"
  end

  private

  # 自ユーザー配下の従業員をIDで取得する（他ユーザーの従業員は対象外）
  def set_employee
    @employee = current_user.employees.find(params[:id])
  end

  # フォームの店舗選択肢用に自ユーザーの店舗一覧をセットする
  def set_stores
    @stores = current_user.stores
  end

  def employee_params
    p = params.require(:employee).permit(:code, :name, :pin, :pin_confirmation, :is_all_stores, store_ids: [])
    # 空文字の場合は nil に変換（PINなし従業員として登録）
    p[:pin] = nil if p[:pin].blank?
    p[:pin_confirmation] = nil if p[:pin_confirmation].blank?
    # 全店舗フラグがONの場合、現在のユーザーの全店舗を紐付ける
    if p[:is_all_stores] == "1"
      p[:store_ids] = current_user.stores.ids
    end
    p
  end

  # PERMISSION_CATALOG のキーに限定したチェックボックス値を取得する
  def permission_params
    Array(params.dig(:employee, :permission_keys)).select { |k| Employee::PERMISSION_CATALOG.key?(k) }
  end
end
