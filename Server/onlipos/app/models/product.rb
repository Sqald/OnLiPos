require 'csv'

class Product < ApplicationRecord
  belongs_to :user
  has_many :store_stocks, dependent: :destroy
  has_many :prices, dependent: :destroy
  has_many :saledetails
  has_many :stores, through: :store_stocks

  validates :code, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }

  enum :status, { active: 0, discontinued: 1 }

  def status_i18n
    status == "active" ? "有効" : "廃盤"
  end

  # CSVインポート処理
  def self.import(file, user)
    imported_count = 0
    skipped_codes = []
    errors = []

    # headers: true で1行目をヘッダーとして扱います
    # with_index(2) で行番号を2から開始します (エラー表示用)
    # BOM|UTF-8 でBOM付きファイルも許容する
    path = file.respond_to?(:path) ? file.path : file
    CSV.foreach(path, headers: true, encoding: 'BOM|UTF-8').with_index(2) do |row, row_num|
      # 既存の商品コードがある場合はスキップ
      if user.products.exists?(code: row["code"])
        skipped_codes << row["code"]
        next
      end

      product = user.products.new
      # CSVのカラムと属性をマッピング
      product.attributes = row.to_hash.slice(*updatable_attributes)

      if product.save
        imported_count += 1
      else
        errors << "L#{row_num}: #{product.errors.full_messages.join(', ')}"
      end
    end
    { imported_count: imported_count, skipped: skipped_codes, errors: errors }
  end

  # CSVで許可する属性のリスト
  def self.updatable_attributes
    ["code", "name", "price", "description", "status"]
  end
end