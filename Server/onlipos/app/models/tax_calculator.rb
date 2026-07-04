# 消費税計算の共通ロジック。
# 明細行を（税率, 税区分）ごとにまとめ、インボイス制度の
# 「1レシートにつき税率ごとに端数処理1回」を満たす税率別内訳を計算する。
# 端数処理方式は企業設定（users.tax_rounding_method）に従う。
#
# 誤差を避けるため Rational で計算し、丸めの瞬間だけ整数化する。
class TaxCalculator
  Breakdown = Struct.new(:tax_rate, :tax_type, :taxable_amount, :amount_ex_tax, :tax_amount, keyword_init: true)

  # rounding_method: "round_down"(切捨て) / "round_half_up"(四捨五入) / "round_up"(切上げ)
  def initialize(rounding_method)
    @rounding_method = rounding_method.to_s
  end

  # lines: [{ amount:, tax_rate:, tax_type: }] の配列。
  # amount は内税(inclusive)なら税込額、外税(exclusive)なら税抜額、非課税(tax_free)ならそのままの額。
  # 戻り値は税率昇順の Breakdown 配列。
  def breakdowns(lines)
    grouped = lines.group_by { |line| [ line[:tax_rate].to_i, line[:tax_type].to_s ] }

    grouped.map { |(tax_rate, tax_type), group|
      amount = group.sum { |line| line[:amount].to_i }

      case tax_type
      when "exclusive"
        tax = round_tax(Rational(amount * tax_rate, 100))
        Breakdown.new(tax_rate: tax_rate, tax_type: tax_type,
                      taxable_amount: amount + tax, amount_ex_tax: amount, tax_amount: tax)
      when "tax_free"
        Breakdown.new(tax_rate: tax_rate, tax_type: tax_type,
                      taxable_amount: amount, amount_ex_tax: amount, tax_amount: 0)
      else # "inclusive"
        tax = round_tax(Rational(amount * tax_rate, 100 + tax_rate))
        Breakdown.new(tax_rate: tax_rate, tax_type: tax_type,
                      taxable_amount: amount, amount_ex_tax: amount - tax, tax_amount: tax)
      end
    }.sort_by { |b| [ b.tax_rate, b.tax_type ] }
  end

  # 明細1行分の税額（表示用）。内訳の確定値とは独立に、行単位の参考値として使う
  def line_tax(amount, tax_rate, tax_type)
    case tax_type.to_s
    when "exclusive" then round_tax(Rational(amount * tax_rate, 100))
    when "tax_free"  then 0
    else round_tax(Rational(amount * tax_rate, 100 + tax_rate))
    end
  end

  private

  def round_tax(value)
    case @rounding_method
    when "round_half_up" then value.round
    when "round_up"      then value.ceil
    else                      value.floor
    end
  end
end
