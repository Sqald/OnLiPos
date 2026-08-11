require "csv"

# 商品マスタ。User（企業）に属し、店舗ごとの在庫（StoreStock）・価格（Price）を持つ。
# CSVによる一括インポート/エクスポートにも対応する。
class Product < ApplicationRecord
  belongs_to :user
  belongs_to :product_category, optional: true
  has_many :store_stocks, dependent: :destroy
  has_many :prices, dependent: :destroy
  has_many :saledetails
  has_many :stores, through: :store_stocks

  validates :code, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  enum :status, { active: 0, discontinued: 1 }

  # 税区分（0: 内税 = 現行既定, 1: 外税, 2: 非課税）
  enum :tax_type, { inclusive: 0, exclusive: 1, tax_free: 2 }, prefix: :tax

  # 量り売り（計量）商品。true の場合、price は「100gあたりの単価」として扱う
  # （寺岡精工の対面計量POS等に見られる方式）。会計時は重量(g)を入力して金額を算出する。

  # status を日本語表示用の文字列に変換する
  def status_i18n
    status == "active" ? "有効" : "廃盤"
  end

  # CSVインポート処理（既存商品は更新、新規商品は追加）
  def self.import(file, user)
    imported_count = 0
    updated_count = 0
    errors = []

    # headers: true で1行目をヘッダーとして扱います
    # with_index(2) で行番号を2から開始します（エラー表示用）
    # BOM|UTF-8 でBOM付きファイルも許容する
    path = file.respond_to?(:path) ? file.path : file
    CSV.foreach(path, headers: true, encoding: "BOM|UTF-8").with_index(2) do |row, row_num|
      attrs = row.to_hash.slice(*updatable_attributes)
      code = attrs["code"].to_s.strip
      next if code.blank?

      product = user.products.find_or_initialize_by(code: code)
      is_new = product.new_record?
      product.attributes = attrs

      if product.save
        is_new ? imported_count += 1 : updated_count += 1
      else
        errors << "L#{row_num}: #{product.errors.full_messages.join(', ')}"
      end
    end
    { imported_count: imported_count, updated_count: updated_count, errors: errors }
  end

  # CSVで許可する属性のリスト
  def self.updatable_attributes
    [ "code", "name", "price", "description", "status", "tax_rate", "sold_by_weight" ]
  end
end
