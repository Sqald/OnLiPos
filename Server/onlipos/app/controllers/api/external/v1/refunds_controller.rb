class Api::External::V1::RefundsController < Api::External::V1::BaseController
  before_action { require_scope!("sales:read") }

  def index
    page = paginate(date_range("refunds.business_date", Refund.where(user: account)).includes(:refund_details, :refund_payments))
    render json: { refunds: page[:records].map { |r| SalePayload.refund(r) }, next_after_id: page[:next_after_id] }
  end
end
