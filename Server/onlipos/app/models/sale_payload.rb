# 外部連携（Webhook・外部API）に渡す会計・返品の内容
module SalePayload
  module_function

  def sale(sale)
    {
      id: sale.id, receipt_number: sale.receipt_number, status: sale.status, store_id: sale.store_id, store_name: sale.store.name,
      business_date: sale.business_date, sold_at: sale.sold_at&.iso8601, total_amount: sale.total_amount, tax_amount: sale.tax_amount,
      total_discount: sale.total_discount, customer_code: sale.customer&.code, voided_at: sale.voided_at&.iso8601,
      details: sale.saledetails.map { |d|
        { product_id: d.product_id, product_code: d.product&.code, product_name: d.product_name, quantity: d.quantity, unit_price: d.unit_price,
          subtotal: d.subtotal, tax_rate: d.tax_rate, tax_type: d.tax_type, service_type: d.service_type, options: d.options }
      },
      payments: sale.sale_payments.map { |p| { method: p.method, amount: p.amount } }
    }
  end

  def refund(refund)
    {
      id: refund.id, refund_receipt_number: refund.refund_receipt_number, sale_id: refund.sale_id, store_id: refund.store_id,
      business_date: refund.business_date, refunded_at: refund.refunded_at&.iso8601, total_amount: refund.total_amount,
      details: refund.refund_details.map { |d| { product_id: d.product_id, product_name: d.product_name, quantity: d.quantity, subtotal: d.subtotal } },
      payments: refund.refund_payments.map { |p| { method: p.method, amount: p.amount } }
    }
  end
end
