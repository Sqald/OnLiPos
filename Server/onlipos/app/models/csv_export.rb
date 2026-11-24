require "csv"

# CSV出力の共通処理。Excel等での文字化け防止のBOM付与と、数式として実行される値の無害化を行う。
module CsvExport
  DANGEROUS = /\A[=+\-@\t\r]/

  def self.cell(value)
    value.is_a?(String) && value.match?(DANGEROUS) ? "'#{value}" : value
  end

  # ブロックに追記用オブジェクトを渡し、CSV文字列を返す
  def self.generate(headers = nil, encoding: nil)
    body = CSV.generate do |csv|
      csv << headers if headers
      yield Writer.new(csv)
    end
    encoding ? body.encode(encoding, undef: :replace, invalid: :replace, replace: "?") : "﻿#{body}"
  end

  Writer = Struct.new(:csv) do
    def <<(row)
      csv << row.map { |value| CsvExport.cell(value) }
      self
    end
  end
end
