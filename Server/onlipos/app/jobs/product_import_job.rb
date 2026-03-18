class ProductImportJob < ApplicationJob
  queue_as :default

  def perform(file_path, user_id, lock_key)
    user = User.find(user_id)

    # インポート処理を実行
    result = Product.import(file_path, user)

    # ログに結果を出力 (サーバーログで確認可能)
    Rails.logger.info "CSV Import Finished: #{result[:imported_count]} imported, #{result[:skipped].size} skipped, #{result[:errors].size} errors."
    if result[:errors].any?
      Rails.logger.error "CSV Import Errors: #{result[:errors].join(', ')}"
    end

    # 処理が終わったら一時ファイルを削除
    File.delete(file_path) if File.exist?(file_path)
  rescue => e
    Rails.logger.error "CSV Import Failed: #{e.message}"
    # エラー時もファイルを削除しておく
    File.delete(file_path) if File.exist?(file_path)
    raise e
  ensure
    Rails.cache.delete(lock_key) if lock_key.present?
  end
end