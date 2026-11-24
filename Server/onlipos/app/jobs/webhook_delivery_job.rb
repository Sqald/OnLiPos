require "net/http"

# Webhook の送信。失敗は間隔を空けて再試行し、続けて失敗した通知先は自動で停止する。
class WebhookDeliveryJob < ApplicationJob
  class DeliveryFailed < StandardError; end

  retry_on DeliveryFailed, wait: :polynomially_longer, attempts: 6 do |_job, _error| end
  discard_on ActiveRecord::RecordNotFound

  def perform(webhook_id, event, payload)
    webhook = Webhook.enabled.find_by(id: webhook_id)
    return unless webhook

    body = { id: job_id, event: event, created_at: Time.current.iso8601, data: payload }.to_json
    deliver(webhook, event, body)
    webhook.update_columns(failure_count: 0, last_delivered_at: Time.current, last_error: nil)
  rescue DeliveryFailed => e
    failures = webhook.failure_count + 1
    webhook.update_columns(failure_count: failures, last_error: e.message.slice(0, 200), active: failures < Webhook::MAX_FAILURES)
    raise
  end

  private

  def deliver(webhook, event, body)
    uri = URI.parse(webhook.url)
    addresses = Webhook.resolve_public(uri.host) or raise DeliveryFailed, "送信先を名前解決できないか、内部アドレスです"
    timestamp = Time.current.to_i

    http = Net::HTTP.new(uri.host, uri.port)
    # 検査したアドレスへ直接接続し、検査後に名前解決の結果が変わる攻撃（DNSリバインディング）を防ぐ
    http.ipaddr = addresses.first.to_s
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10
    request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "User-Agent" => "OnLiPos-Webhook", "X-OnLiPos-Event" => event,
                                       "X-OnLiPos-Timestamp" => timestamp.to_s, "X-OnLiPos-Signature" => webhook.sign(body, timestamp))
    request.body = body
    response = http.request(request)
    raise DeliveryFailed, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  rescue SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, SocketError, IOError => e
    raise DeliveryFailed, e.class.name
  end
end
