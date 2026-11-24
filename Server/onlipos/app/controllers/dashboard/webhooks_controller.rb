# Webhook の通知先（契約者のみ）
class Dashboard::WebhooksController < Dashboard::ResourceController
  requires_role read: "owner", write: "owner"
  before_action :require_recent_authentication, only: [ :create, :update, :destroy ]

  manages Webhook, title: "Webhook",
    description: "会計・返品・在庫不足などを、指定したURLへJSONで通知します。本文は X-OnLiPos-Signature（HMAC-SHA256、対象は「タイムスタンプ.本文」）で検証してください。",
    columns: { "URL" => :url, "イベント" => ->(r, v) { v.safe_join(r.events.map { |e| Webhook::EVENTS[e] }, "、") }, "署名の鍵" => ->(r, v) { v.tag.code(r.secret) },
               "最終送信" => ->(r, v) { v.datetime(r.last_delivered_at) }, "状態" => ->(r, v) { v.badge(r.active ? "有効" : "停止", r.active) + " #{r.last_error}" } },
    fields: [ field(:url, "URL（https）", required: true), field(:events, "通知するイベント", :checkboxes, choices: Webhook::EVENTS.map { |k, v| [ v, k ] }), field(:active, "有効", :checkbox) ]
end
