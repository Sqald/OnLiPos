class Api::External::V1::CustomersController < Api::External::V1::BaseController
  before_action { require_scope!("customers:read") }

  def index
    page = paginate(account.customers.active)
    render json: { customers: page[:records].map { |c| c.slice(:id, :code, :name, :phone, :email, :points, :visits_count).merge(last_visited_at: c.last_visited_at&.iso8601) }, next_after_id: page[:next_after_id] }
  end
end
