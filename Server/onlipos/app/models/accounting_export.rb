# 売上・返品の仕訳データ（日次・店舗別）を作る。
#   借方: 決済手段ごとの入金（現金・売掛金など） / 貸方: 税率ごとの売上高
#   返品は逆仕訳、レジの過不足は「現金過不足」で計上する。
class AccountingExport
  FORMATS = { "generic" => "汎用CSV", "freee" => "freee（仕訳帳インポート）", "moneyforward" => "マネーフォワード（仕訳帳）", "yayoi" => "弥生会計（仕訳日記帳）" }.freeze

  DEBIT_ACCOUNTS = {
    "cash" => "現金", "card" => "売掛金", "barcode" => "売掛金", "emoney" => "売掛金",
    "points" => "販売促進費", "voucher" => "仮払金", "house_account" => "売掛金"
  }.freeze

  Entry = Struct.new(:date, :debit, :debit_sub, :debit_tax, :credit, :credit_sub, :credit_tax, :amount, :tax, :memo, keyword_init: true)

  def initialize(account, from:, to:, store_ids:)
    @account = account
    @range = from..to
    @from = from
    @to = to
    @stores = account.stores.where(id: store_ids).order(:id).to_a
  end

  # 1行1仕訳（諸口を使う複合仕訳を避け、どの会計ソフトでも取り込めるようにする）
  def entries
    @stores.flat_map { |store| (store_entries(store, :sale) + store_entries(store, :refund) + cash_difference_entries(store)) }.sort_by { |e| [ e.date, e.memo ] }
  end

  def to_file(format)
    raise ArgumentError, "不明な形式です" unless FORMATS.key?(format)

    [ public_send(:"#{format}_csv"), "journal_#{format}_#{@from}_#{@to}.csv" ]
  end

  def generic_csv
    CsvExport.generate(%w[日付 借方勘定科目 借方補助科目 借方税区分 貸方勘定科目 貸方補助科目 貸方税区分 金額 うち消費税 摘要]) do |csv|
      entries.each { |e| csv << [ e.date, e.debit, e.debit_sub, e.debit_tax, e.credit, e.credit_sub, e.credit_tax, e.amount, e.tax, e.memo ] }
    end
  end

  def freee_csv
    headers = %w[日付 伝票番号 決算整理仕訳 借方勘定科目 借方補助科目 借方金額 借方税区分 借方税額 貸方勘定科目 貸方補助科目 貸方金額 貸方税区分 貸方税額 摘要]
    CsvExport.generate(headers) do |csv|
      entries.each.with_index(1) do |e, i|
        debit_sale, credit_sale = [ e.debit, e.credit ].map { |name| name == "売上高" }
        csv << [ e.date.strftime("%Y/%m/%d"), i, "", e.debit, e.debit_sub, e.amount, e.debit_tax, (e.tax if debit_sale), e.credit, e.credit_sub, e.amount, e.credit_tax, (e.tax if credit_sale), e.memo ]
      end
    end
  end

  def moneyforward_csv
    headers = %w[取引No 取引日 借方勘定科目 借方補助科目 借方部門 借方取引先 借方税区分 借方インボイス 借方金額(円) 借方税額 貸方勘定科目 貸方補助科目 貸方部門 貸方取引先 貸方税区分 貸方インボイス 貸方金額(円) 貸方税額 摘要]
    CsvExport.generate(headers) do |csv|
      entries.each.with_index(1) do |e, i|
        csv << [ i, e.date.strftime("%Y/%m/%d"), e.debit, e.debit_sub, "", "", e.debit_tax, "", e.amount, (e.tax if e.debit == "売上高"),
                 e.credit, e.credit_sub, "", "", e.credit_tax, "", e.amount, (e.tax if e.credit == "売上高"), e.memo ]
      end
    end
  end

  # 弥生会計のインポート形式（見出しなし・25列・Shift_JIS）
  def yayoi_csv
    CsvExport.generate(encoding: Encoding::Windows_31J) do |csv|
      entries.each.with_index(1) do |e, i|
        csv << [ "2000", i, "", e.date.strftime("%Y/%m/%d"), e.debit, e.debit_sub, "", e.debit_tax, e.amount, (e.tax if e.debit == "売上高").to_i,
                 e.credit, e.credit_sub, "", e.credit_tax, e.amount, (e.tax if e.credit == "売上高").to_i, e.memo, "", "", "0", "", "", "0", "0", "no" ]
      end
    end
  end

  private

  # 決済手段と税率の組み合わせに按分して1行1仕訳にする（端数は最後の行に寄せる）
  def store_entries(store, kind)
    per_day(store, kind).flat_map do |date, (payments, taxes)|
      total = payments.sum { |_, amount| amount }
      next [] if total.zero?

      payments.flat_map do |method, amount|
        shares = allocate(amount, taxes, total)
        shares.map { |tax, share, share_tax| build_entry(store, kind, date, method, tax, share, share_tax) }
      end
    end
  end

  # taxes: [[税率, 税区分], 金額, 税額] の配列
  def allocate(amount, taxes, total)
    left = amount
    rows = taxes.each_with_index.map do |(key, taxable, tax), index|
      share = index == taxes.size - 1 ? left : amount * taxable / total
      left -= share
      [ key, share, taxable.zero? ? 0 : (Rational(tax * share, taxable)).floor ]
    end
    rows.reject { |_, share, _| share.zero? }
  end

  def per_day(store, kind)
    if kind == :sale
      scope = Sale.completed.where(store: store, business_date: @range)
      payments = SalePayment.joins(:sale).merge(scope).group("sales.business_date", :method).sum(:amount)
      taxes = SaleTaxBreakdown.joins(:sale).merge(scope).group("sales.business_date", :tax_rate, :tax_type)
    else
      scope = Refund.where(store: store, business_date: @range)
      payments = RefundPayment.joins(:refund).merge(scope).group("refunds.business_date", :method).sum(:amount)
      taxes = RefundTaxBreakdown.joins(:refund).merge(scope).group("refunds.business_date", :tax_rate, :tax_type)
    end
    amounts = taxes.sum(:taxable_amount)
    tax_amounts = taxes.sum(:tax_amount)

    dates = payments.keys.map(&:first).uniq.sort
    dates.to_h do |date|
      day_payments = payments.filter_map { |(d, method), amount| [ method.to_s, amount ] if d == date }
      day_taxes = amounts.filter_map { |(d, rate, type), amount| [ [ rate, type.to_s ], amount, tax_amounts[[ d, rate, type ]].to_i ] if d == date }
      [ date, [ day_payments, day_taxes.presence || [ [ [ 0, "tax_free" ], day_payments.sum(&:last), 0 ] ] ] ]
    end
  end

  def build_entry(store, kind, date, method, (rate, type), amount, tax)
    account = DEBIT_ACCOUNTS.fetch(method, "売掛金")
    label = PaymentMethods.label(method)
    sub = account == "現金" ? store.name : label
    sales_tax = type == "tax_free" ? "非課税売上" : tax_category(rate)
    memo = "#{store.name} #{kind == :sale ? "売上" : "返品"} #{label} #{type == "tax_free" ? "非課税" : "#{rate}%"}"
    if kind == :sale
      Entry.new(date: date, debit: account, debit_sub: sub, debit_tax: "対象外", credit: "売上高", credit_sub: store.name, credit_tax: sales_tax, amount: amount, tax: tax, memo: memo)
    else
      Entry.new(date: date, debit: "売上高", debit_sub: store.name, debit_tax: sales_tax.sub("課税売上", "課税売上返還"), credit: account, credit_sub: sub, credit_tax: "対象外", amount: amount, tax: tax, memo: memo)
    end
  end

  def tax_category(rate)
    rate == 8 || rate == 1 ? "課税売上#{rate}%（軽）" : "課税売上#{rate}%"
  end

  def cash_difference_entries(store)
    RegisterSession.closed.where(store: store, business_date: @range).where.not(cash_diff_amount: [ nil, 0 ]).map do |s|
      over = s.cash_diff_amount.positive?
      Entry.new(date: s.business_date, debit: over ? "現金" : "現金過不足", debit_sub: over ? store.name : "", debit_tax: "対象外",
                credit: over ? "現金過不足" : "現金", credit_sub: over ? "" : store.name, credit_tax: "対象外",
                amount: s.cash_diff_amount.abs, tax: 0, memo: "#{store.name} #{s.pos_token.name} Z#{s.z_number} 現金過不足")
    end
  end
end
