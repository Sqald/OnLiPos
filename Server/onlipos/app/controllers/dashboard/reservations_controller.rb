# 予約
class Dashboard::ReservationsController < Dashboard::ResourceController
  manages Reservation, title: "予約", order: :starts_at,
    columns: { "日時" => ->(r, v) { v.datetime(r.starts_at) }, "店舗" => ->(r, _) { r.store.name }, "名前" => :name, "電話" => :phone, "人数" => :party_size, "卓" => :table_number,
               "状態" => ->(r, _) { Reservation::STATUS_LABELS[r.status] }, "メモ" => :note },
    fields: [ field(:store_id, "店舗", :select, choices: -> { current_account.stores.order(:name).pluck(:name, :id) }), field(:name, "名前", required: true), field(:phone, "電話番号"),
              field(:party_size, "人数", :number, min: 1), field(:table_number, "卓番号"), field(:starts_at, "開始", :datetime, required: true), field(:ends_at, "終了（空欄 = 2時間）", :datetime),
              field(:status, "状態", :select, choices: Reservation::STATUS_LABELS.map { |k, v| [ v, k ] }), field(:note, "メモ", :textarea, rows: 3) ]

  private

  def scope = Reservation.where(store: current_account.stores).includes(:store)
  def filtered_scope = params[:all] ? scope : scope.where(starts_at: Time.current.beginning_of_day..)
end
