# 商品CSVの取込。web と worker は別コンテナで動くため、内容はファイルではなくDBで受け渡す。
class ProductImport < ApplicationRecord
  MAX_SIZE = 5.megabytes
  MAX_ERRORS = 200

  belongs_to :user
  enum :status, { queued: 0, running: 1, completed: 2, failed: 3 }

  scope :unfinished, -> { where(status: %i[queued running]).where("updated_at > ?", 1.hour.ago) }

  # アップロードされたファイルをUTF-8に直す（Excel が出力する Shift_JIS にも対応）
  def self.decode(bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
    return text if text.valid_encoding?

    bytes.dup.force_encoding(Encoding::Windows_31J).encode(Encoding::UTF_8)
  end

  def run!
    update!(status: :running)
    result = Product.import_csv(content, user)
    update!(status: :completed, imported_count: result[:imported_count], updated_count: result[:updated_count],
            error_messages: result[:errors].first(MAX_ERRORS), finished_at: Time.current, content: nil)
  rescue => e
    update!(status: :failed, error_messages: [ "取込に失敗しました: #{e.message.slice(0, 200)}" ], finished_at: Time.current, content: nil)
  end
end
