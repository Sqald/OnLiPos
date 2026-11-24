# 勤怠の一覧・修正・CSV出力
class Dashboard::AttendancesController < Dashboard::BaseController
  def index
    @stores = current_account.stores.order(:name)
    @from = parse_date(params[:from]) || Date.current.beginning_of_month
    @to = parse_date(params[:to]) || Date.current
    scope = Attendance.joins(:store).where(stores: { user_id: current_account.id }, clock_in_at: @from.beginning_of_day..@to.end_of_day).includes(:employee, :store)
    scope = scope.where(store_id: params[:store_id]) if params[:store_id].present?
    scope = scope.order(:clock_in_at)

    respond_to do |format|
      format.html do
        @attendances = scope.page(params[:page]).per(100)
        @totals = scope.to_a.group_by(&:employee).map { |employee, rows| [ employee, rows.size, rows.sum { |r| r.worked_minutes.to_i } ] }
      end
      format.csv { send_data attendance_csv(scope), filename: "attendances_#{@from}_#{@to}.csv", type: "text/csv; charset=UTF-8" }
    end
  end

  def update
    attendance = Attendance.joins(:store).where(stores: { user_id: current_account.id }).readonly(false).find(params[:id])
    attendance.assign_attributes(params.require(:attendance).permit(:clock_in_at, :clock_out_at, :break_minutes).merge(corrected_by_name: current_user.display_name))
    changes = attendance.changes.except("corrected_by_name")
    if attendance.save
      AuditLog.record("update", target: attendance, details: changes.merge("従業員" => attendance.employee.name))
      redirect_back fallback_location: dashboard_attendances_path, notice: "修正しました。", status: :see_other
    else
      redirect_back fallback_location: dashboard_attendances_path, alert: attendance.errors.full_messages.join("、"), status: :see_other
    end
  end

  private

  def attendance_csv(scope)
    CsvExport.generate(%w[従業員コード 従業員 店舗 出勤 退勤 休憩（分） 実働（分） 修正者]) do |csv|
      scope.each { |a| csv << [ a.employee.code, a.employee.name, a.store.name, a.clock_in_at, a.clock_out_at, a.break_minutes, a.worked_minutes, a.corrected_by_name ] }
    end
  end
end
