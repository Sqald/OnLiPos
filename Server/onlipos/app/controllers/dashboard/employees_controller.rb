class Dashboard::EmployeesController < Dashboard::BaseController
  before_action :set_employee, only: [:edit, :update, :destroy]
  before_action :set_stores, only: [:new, :create, :edit, :update]

  def index
    @employees = current_user.employees
  end

  def new
    @employee = current_user.employees.build
  end

  def create
    @employee = current_user.employees.build(employee_params)
    if @employee.save
      redirect_to dashboard_employees_path, notice: '従業員を登録しました。'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @employee.update(employee_params)
      redirect_to dashboard_employees_path, notice: '従業員情報を更新しました。'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @employee.destroy
    redirect_to dashboard_employees_path, notice: '従業員を削除しました。'
  end

  private

  def set_employee
    @employee = current_user.employees.find(params[:id])
  end

  def set_stores
    @stores = current_user.stores
  end

  def employee_params
    p = params.require(:employee).permit(:code, :name, :pin, :pin_confirmation, :is_all_stores, store_ids: [])
    # 空文字の場合は nil に変換（PINなし従業員として登録）
    p[:pin] = nil if p[:pin].blank?
    p[:pin_confirmation] = nil if p[:pin_confirmation].blank?
    # 全店舗フラグがONの場合、現在のユーザーの全店舗を紐付ける
    if p[:is_all_stores] == '1'
      p[:store_ids] = current_user.stores.ids
    end
    p
  end
end
