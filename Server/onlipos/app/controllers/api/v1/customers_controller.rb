# 会員の検索・登録。検索は会員番号・電話番号の一致のみ（氏名の一覧を端末から取り出せないようにする）
class Api::V1::CustomersController < Api::V1::BaseController
  def index
    term = params[:q].to_s.strip
    return render json: { success: false, message: "会員番号または電話番号を入力してください" }, status: :bad_request if term.length < 4

    customers = account.customers.active.where("code = :q OR phone = :q", q: term).limit(5)
    render json: { success: true, customers: customers.map { |c| customer_json(c) } }
  end

  def create
    customer = account.customers.build(params.permit(:name, :phone, :email))
    if customer.save
      render json: { success: true, customer: customer_json(customer) }, status: :created
    else
      render json: { success: false, message: customer.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  private

  def account = @current_pos.store.user

  def customer_json(customer)
    { code: customer.code, name: customer.name, points: customer.points, credit_allowed: customer.credit_allowed, receivable: customer.receivable }
  end
end
