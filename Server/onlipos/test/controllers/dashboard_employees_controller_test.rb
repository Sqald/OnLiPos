require "test_helper"

class DashboardEmployeesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def create_user(login_name)
    User.create!(
      login_name: login_name,
      email: "#{login_name}@example.com",
      password: "Password1!",
      password_confirmation: "Password1!",
      first_name: "太郎",
      last_name: "従業員",
      user_type: :individual,
      confirmed_at: Time.current
    )
  end

  setup do
    @user = create_user("dashemptest")
    @store = @user.stores.create!(name: "自店舗", ascii_name: "mystore")
    @other_store = create_user("dashempother").stores.create!(name: "他社店舗", ascii_name: "otherstore")
    sign_in @user
  end

  test "他ユーザーの店舗IDを指定しても従業員に紐付かない" do
    post dashboard_employees_path, params: {
      employee: { code: "E100", name: "新人", is_all_stores: "0", store_ids: [ @store.id, @other_store.id ] }
    }

    employee = @user.employees.find_by(code: "E100")
    assert employee
    assert_equal [ @store.id ], employee.store_ids
  end

  test "CSP ヘッダーが付与され、フォームにインラインスクリプトが含まれない" do
    get new_dashboard_employee_path

    assert_response :ok
    csp = response.headers["Content-Security-Policy"]
    assert_includes csp, "script-src 'self'"
    assert_includes csp, "object-src 'none'"
    assert_no_match(/onclick=|<script>/, response.body)
    assert_includes response.body, 'data-controller="store-select"'
  end
end
