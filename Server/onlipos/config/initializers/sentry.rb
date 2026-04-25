# Sentry はオプションです。SENTRY_DSN を設定した場合のみ有効になります。
if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.enabled_environments = %w[production]

    config.breadcrumbs_logger = [:active_support_logger, :http_logger]

    # 個人情報をSentryに送らないよう、パラメータをフィルタリング
    config.send_default_pii = false

    # パフォーマンス監視（サンプリング率10%）
    config.traces_sample_rate = 0.1
  end
end
