# 期限切れデータの削除（承認トークン・古い価格履歴）
class CleanupJob < ApplicationJob
  def perform
    OperatorApproval.purge_expired!
    ProductPriceHistory.where("replaced_at < ?", 1.year.ago).in_batches.delete_all
  end
end
