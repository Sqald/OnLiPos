# 勤怠の打刻（従業員コード＋PIN）
class Api::V1::AttendancesController < Api::V1::BaseController
  include EmployeePinAuthenticatable

  # 勤務中の従業員
  def index
    rows = Attendance.open.where(store_id: @current_pos.store_id).includes(:employee).order(:clock_in_at)
    render json: { success: true, attendances: rows.map { |a| { employee_name: a.employee.name, clock_in_at: a.clock_in_at, on_break: a.break_started_at.present? } } }
  end

  def create
    employee = authenticated_employee
    return unless employee

    attendance = Attendance.punch!(params[:punch].to_s, employee: employee, store: @current_pos.store, pos_token: @current_pos)
    render json: { success: true, employee_name: employee.name, punch: params[:punch], clock_in_at: attendance.clock_in_at, clock_out_at: attendance.clock_out_at,
                   break_minutes: attendance.break_minutes, worked_minutes: attendance.worked_minutes }, status: :created
  rescue Attendance::Error => e
    render json: { success: false, message: e.message }, status: :unprocessable_entity
  end
end
