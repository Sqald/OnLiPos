# 仕入先
class Dashboard::SuppliersController < Dashboard::ResourceController
  manages Supplier, title: "仕入先", order: :name,
    columns: { "名称" => :name, "担当者" => :contact_name, "電話" => :phone, "メール" => :email, "登録番号" => :invoice_registration_number,
               "状態" => ->(r, v) { v.badge(r.active ? "取引中" : "停止", r.active) } },
    fields: [ field(:name, "名称", required: true), field(:contact_name, "担当者"), field(:phone, "電話番号"), field(:email, "メールアドレス"),
              field(:invoice_registration_number, "インボイス登録番号", placeholder: "T1234567890123"), field(:note, "メモ", :textarea, rows: 3), field(:active, "取引中", :checkbox) ]
end
