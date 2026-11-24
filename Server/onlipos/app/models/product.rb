require "csv"

# 商品マスタ。User（企業）に属し、店舗ごとの在庫（StoreStock）・価格（Price）を持つ。
# CSVによる一括インポート/エクスポートにも対応する。
class Product < ApplicationRecord
  include Auditable
  # アソシエーション
  belongs_to :user
  belongs_to :product_category, optional: true
  # 売上明細の「何を」を失わないよう、販売履歴のある商品は削除できない（廃盤にして運用する）。
  # 在庫・価格の削除より先に判定させるため先頭で宣言する
  has_many :saledetails, dependent: :restrict_with_error
  has_many :store_stocks, dependent: :destroy
  has_many :prices, dependent: :destroy
  has_many :stores, through: :store_stocks
  has_many :scheduled_product_changes, dependent: :delete_all
  has_many :purchase_order_items, dependent: :restrict_with_error
  has_many :stocktake_items, dependent: :restrict_with_error
  has_and_belongs_to_many :option_groups
  has_and_belongs_to_many :promotions
  belongs_to :supplier, optional: true
  has_one_attached :image

  IMAGE_TYPES = %w[image/png image/jpeg image/webp].freeze
  IMAGE_MAX_SIZE = 3.megabytes

  # 予約された変更の適用時刻（価格履歴に記録する）。通常の変更では nil
  attr_accessor :effective_at

  # バリデーション
  validates :code, presence: true, uniqueness: { scope: :user_id }
  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :tax_rate, numericality: { only_integer: true, in: 0..100 }
  validates :eat_in_tax_rate, numericality: { only_integer: true, in: 0..100 }, allow_nil: true
  validates :eat_in_price, :cost_price, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :min_age, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validates :low_stock_threshold, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :image_must_be_acceptable
  validate { errors.add(:supplier, "が不正です") if supplier && supplier.user_id != user_id }
  validate :product_category_must_belong_to_same_user

  enum :status, { active: 0, discontinued: 1 }

  # 税区分（0: 内税 = 現行既定, 1: 外税, 2: 非課税）
  enum :tax_type, { inclusive: 0, exclusive: 1, tax_free: 2 }, prefix: :tax

  # 価格・税率を変更したら、変更前の値を履歴に残す（SalePricePolicy で使う）
  after_update :record_price_history, if: -> { (saved_changes.keys & %w[price tax_rate tax_type eat_in_price eat_in_tax_rate]).any? }

  # 量り売り（計量）商品。true の場合、price は「100gあたりの単価」として扱う
  # （寺岡精工の対面計量POS等に見られる方式）。会計時は重量(g)を入力して金額を算出する。

  # status を日本語表示用の文字列に変換する
  def status_i18n
    status == "active" ? "有効" : "廃盤"
  end

  TAX_TYPE_LABELS = { "inclusive" => "内税", "exclusive" => "外税", "tax_free" => "非課税" }.freeze
  def self.tax_type_label(type) = TAX_TYPE_LABELS.fetch(type.to_s, type)

  # 店内飲食の税率・価格（未設定なら通常と同じ）
  def tax_rate_for(eat_in) = (eat_in && eat_in_tax_rate) || tax_rate

  def profit_rate
    return if cost_price.nil? || price.zero?

    ((price - cost_price) * 100.0 / price).round(1)
  end

  # CSVインポート処理（既存商品は更新、新規商品は追加）
  # カテゴリ・仕入先は名前で指定する（カテゴリは無ければ作成する）。空欄の列は変更しない。
  def self.import_csv(text, user)
    result = { imported_count: 0, updated_count: 0, errors: [] }
    categories = user.product_categories.index_by(&:name)
    suppliers = user.suppliers.index_by(&:name)

    # with_index(2) で行番号を2から開始します（1行目はヘッダー。エラー表示用）
    CSV.parse(text, headers: true, skip_blanks: true).each.with_index(2) do |row, row_num|
      attrs = row.to_hash.slice(*updatable_attributes).transform_values { |v| v&.strip }.compact_blank
      code = attrs["code"]
      next if code.blank?

      product = user.products.find_or_initialize_by(code: code)
      is_new = product.new_record?
      begin
        product.assign_attributes(attrs)
        if (name = row["category"].presence&.strip)
          product.product_category = categories[name] ||= user.product_categories.create!(name: name)
        end
        if (name = row["supplier"].presence&.strip)
          product.supplier = suppliers[name] or raise ArgumentError, "仕入先「#{name}」が登録されていません"
        end
        product.save!
        result[is_new ? :imported_count : :updated_count] += 1
      rescue ActiveRecord::RecordInvalid => e
        result[:errors] << "#{row_num}行目: #{e.record.errors.full_messages.join('、')}"
      rescue ArgumentError => e
        result[:errors] << "#{row_num}行目: #{e.message}"
      end
    end
    result
  end

  # CSVで許可する属性のリスト
  def self.updatable_attributes
    %w[code name price description status tax_rate tax_type sold_by_weight cost_price eat_in_tax_rate eat_in_price min_age
       low_stock_threshold variant_group variant_name track_stock]
  end

  CSV_HEADERS = %w[code name price description status tax_rate tax_type category supplier sold_by_weight cost_price eat_in_tax_rate eat_in_price
                   min_age low_stock_threshold variant_group variant_name track_stock].freeze

  def self.export_csv(scope)
    CsvExport.generate(CSV_HEADERS) do |csv|
      scope.includes(:product_category, :supplier).find_each do |p|
        csv << CSV_HEADERS.map { |h| { "category" => p.product_category&.name, "supplier" => p.supplier&.name }.fetch(h) { p.public_send(h) } }
      end
    end
  end

  private

  def image_must_be_acceptable
    return unless image.attached? && attachment_changes["image"]

    errors.add(:image, "は PNG / JPEG / WebP を指定してください") unless IMAGE_TYPES.include?(image.content_type)
    errors.add(:image, "は3MB以内にしてください") if image.byte_size > IMAGE_MAX_SIZE
  end

  def record_price_history
    ProductPriceHistory.create!(
      product: self,
      price: price_before_last_save,
      tax_rate: tax_rate_before_last_save,
      tax_type: tax_type_before_last_save && self.class.tax_types[tax_type_before_last_save],
      eat_in_price: eat_in_price_before_last_save,
      eat_in_tax_rate: eat_in_tax_rate_before_last_save,
      replaced_at: effective_at || Time.current
    )
  end

  # 他ユーザーのカテゴリを指定できないようにする（カテゴリ名の漏えい防止）
  def product_category_must_belong_to_same_user
    return if product_category.nil? || product_category.user_id == user_id

    errors.add(:product_category_id, "は自分のカテゴリのみ指定できます")
  end
end
