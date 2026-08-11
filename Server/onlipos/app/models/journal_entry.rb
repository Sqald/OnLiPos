# 電子ジャーナル（レシート・レジ操作の改ざん防止付き記録）。
# 端末(pos_token)単位の連番とハッシュチェーンを持ち、追記のみ・更新削除不可（readonly?）。
# 売上・返品・レジ開設精算・取消・領収書発行などのイベントごとに create_from_* で生成される。
class JournalEntry < ApplicationRecord
  belongs_to :user
  belongs_to :store
  belongs_to :pos_token
  belongs_to :employee, optional: true

  enum :entry_type, {
    sale:            0,
    refund:          1,
    register_open:   2,
    cash_check:      3,
    cash_pickup:     4,
    register_close:  5,
    void:            6,
    cash_movement:   7,
    receipt_issue:   8
  }

  validates :entry_type, presence: true
  validates :printed_at, presence: true
  validates :payload,    presence: true

  # チェーン先頭エントリの previous_hash
  GENESIS_HASH = ("0" * 64).freeze

  before_create :assign_integrity_chain

  # 電子ジャーナルは追記型。作成後の更新・削除は改ざんとみなし例外にする
  def readonly?
    persisted?
  end

  # ハッシュ計算対象の正規化JSON。
  # JSONB 保存前（シンボルキー）と読み戻し後（文字列キー）で同じ文字列になるよう、
  # キーを文字列化した上で再帰的にソートする。
  def self.canonical_json(value)
    case value
    when Hash
      "{" + value.map { |k, v| [ k.to_s, v ] }
                 .sort_by(&:first)
                 .map { |k, v| "#{k.to_json}:#{canonical_json(v)}" }
                 .join(",") + "}"
    when Array
      "[" + value.map { |v| canonical_json(v) }.join(",") + "]"
    else
      value.to_json
    end
  end

  # このエントリのハッシュを再計算する（保存値との照合にも使う）
  def compute_entry_hash
    data = [
      pos_token_id,
      sequence_number,
      entry_type,
      printed_at.utc.iso8601(6),
      self.class.canonical_json(payload),
      previous_hash
    ].join("|")
    Digest::SHA256.hexdigest(data)
  end

  # 端末単位でチェーン全体を検証し、問題のリストを返す（空なら健全）。
  # 検知できるもの: 連番の欠番・重複、previous_hash の不整合、エントリ本体の改変。
  def self.verify_chain(pos_token)
    issues = []
    previous = nil

    where(pos_token_id: pos_token.id)
      .where.not(sequence_number: nil)
      .order(:sequence_number)
      .each do |entry|
        expected_seq = previous ? previous.sequence_number + 1 : entry.sequence_number
        if entry.sequence_number != expected_seq
          issues << "連番不整合: id=#{entry.id} sequence=#{entry.sequence_number}（期待値 #{expected_seq}）"
        end

        expected_prev = previous ? previous.entry_hash : GENESIS_HASH
        if entry.previous_hash != expected_prev
          issues << "チェーン切断: id=#{entry.id} previous_hash が直前エントリと一致しません"
        end

        if entry.entry_hash != entry.compute_entry_hash
          issues << "改ざん検知: id=#{entry.id} entry_hash が本体と一致しません"
        end

        previous = entry
      end

    issues
  end

  # Sale 作成と同一トランザクション内で呼ぶ
  def self.create_from_sale!(sale, saledetails, payments)
    create!(
      user:           sale.user,
      store:          sale.store,
      pos_token:      sale.pos_token,
      employee:       sale.employee,
      entry_type:     :sale,
      receipt_number: sale.receipt_number,
      printed_at:     sale.created_at || Time.current,
      payload: {
        receipt_number: sale.receipt_number,
        total_amount:   sale.total_amount,
        payment_method: sale.payment_method,
        subtotal_ex_tax: sale.subtotal_ex_tax,
        tax_amount:     sale.tax_amount,
        total_discount: sale.total_discount,
        order_discount_type:   sale.order_discount_type,
        order_discount_value:  sale.order_discount_value,
        order_discount_total:  sale.order_discount_total,
        order_discount_reason: sale.order_discount_reason,
        customer_gender:    sale.customer_gender,
        customer_age_group: sale.customer_age_group,
        employee_name:  sale.employee&.name,
        store_name:     sale.store.name,
        pos_name:       sale.pos_token.name,
        details: saledetails.map { |d|
          {
            product_name:       d.product_name,
            quantity:           d.quantity,
            unit_price:         d.unit_price,
            subtotal:           d.subtotal,
            tax_rate:           d.tax_rate,
            tax_amount:         d.tax_amount,
            discount_amount:    d.discount_amount,
            discount_reason:    d.discount_reason,
            original_unit_price: d.original_unit_price
          }
        },
        payments: payments.map { |p|
          { method: p[:method], amount: p[:amount], label: p[:label] }
        }
      }
    )
  end

  # Refund 作成と同一トランザクション内で呼ぶ
  def self.create_from_refund!(refund, refund_details)
    create!(
      user:           refund.user,
      store:          refund.store,
      pos_token:      refund.pos_token,
      employee:       refund.employee,
      entry_type:     :refund,
      receipt_number: refund.refund_receipt_number,
      printed_at:     refund.created_at || Time.current,
      payload: {
        refund_receipt_number:    refund.refund_receipt_number,
        original_receipt_number:  refund.sale.receipt_number,
        total_amount:             refund.total_amount,
        employee_name:            refund.employee&.name,
        store_name:               refund.store.name,
        pos_name:                 refund.pos_token.name,
        details: refund_details.map { |d|
          {
            product_name: d.product_name,
            quantity:     d.quantity,
            unit_price:   d.unit_price,
            subtotal:     d.subtotal
          }
        }
      }
    )
  end

  # 確定後取消（VOID）と同一トランザクション内で呼ぶ
  def self.create_from_void!(sale, approver_names)
    create!(
      user:           sale.user,
      store:          sale.store,
      pos_token:      sale.pos_token,
      employee:       sale.voided_by_employee,
      entry_type:     :void,
      receipt_number: sale.receipt_number,
      printed_at:     sale.voided_at || Time.current,
      payload: {
        receipt_number: sale.receipt_number,
        total_amount:   sale.total_amount,
        void_reason:    sale.void_reason,
        approver_names: approver_names,
        z_number:       sale.register_session&.z_number,
        employee_name:  sale.voided_by_employee&.name,
        store_name:     sale.store.name,
        pos_name:       sale.pos_token&.name,
        details: sale.saledetails.map { |d|
          {
            product_name: d.product_name,
            quantity:     d.quantity,
            unit_price:   d.unit_price,
            subtotal:     d.subtotal
          }
        }
      }
    )
  end

  # 領収書発行の記録。発行履歴が残ることで再発行（二重発行）を検知・表示できる
  def self.create_from_receipt_issue!(sale, employee:, addressee:, purpose:, reissue:)
    create!(
      user:           sale.user,
      store:          sale.store,
      pos_token:      sale.pos_token,
      employee:       employee,
      entry_type:     :receipt_issue,
      receipt_number: sale.receipt_number,
      printed_at:     Time.current,
      payload: {
        receipt_number: sale.receipt_number,
        total_amount:   sale.total_amount,
        addressee:      addressee,
        purpose:        purpose,
        reissue:        reissue,
        employee_name:  employee&.name,
        store_name:     sale.store.name,
        pos_name:       sale.pos_token&.name
      }
    )
  end

  # CashMovement 作成と同一トランザクション内で呼ぶ
  def self.create_from_cash_movement!(movement)
    create!(
      user:       movement.store.user,
      store:      movement.store,
      pos_token:  movement.pos_token,
      employee:   movement.employee,
      entry_type: :cash_movement,
      printed_at: movement.occurred_at,
      payload: {
        kind:          movement.kind,
        direction:     movement.direction,
        amount:        movement.amount,
        reason:        movement.reason,
        z_number:      movement.register_session&.z_number,
        employee_name: movement.employee&.name,
        store_name:    movement.store.name,
        pos_name:      movement.pos_token.name
      }
    )
  end

  # CashLog 作成と同一トランザクション内で呼ぶ
  # type: :register_open / :cash_check / :cash_pickup / :register_close
  def self.create_from_cash_log!(cash_log, type)
    payload =
      if cash_log.is_pickup
        {
          pickup_amount:  cash_log.pickup_amount,
          pickup_reason:  cash_log.pickup_reason,
          employee_name:  cash_log.employee&.name,
          store_name:     cash_log.pos_token.store.name,
          pos_name:       cash_log.pos_token.name
        }
      else
        {
          total_amount:    cash_log.total_amount,
          # 実査時点の理論在高・過不足（ジャーナルだけで現金照合を再現できるようにする）
          expected_amount: cash_log.expected_amount,
          diff_amount:     cash_log.diff_amount,
          z_number:        cash_log.register_session&.z_number,
          employee_name:  cash_log.employee&.name,
          store_name:     cash_log.pos_token.store.name,
          pos_name:       cash_log.pos_token.name,
          denominations: {
            yen_10000: cash_log.yen_10000,
            yen_5000:  cash_log.yen_5000,
            yen_1000:  cash_log.yen_1000,
            yen_500:   cash_log.yen_500,
            yen_100:   cash_log.yen_100,
            yen_50:    cash_log.yen_50,
            yen_10:    cash_log.yen_10,
            yen_5:     cash_log.yen_5,
            yen_1:     cash_log.yen_1
          }
        }
      end

    create!(
      user:       cash_log.pos_token.store.user,
      store:      cash_log.pos_token.store,
      pos_token:  cash_log.pos_token,
      employee:   cash_log.employee,
      entry_type: type,
      printed_at: cash_log.created_at || Time.current,
      payload:    payload
    )
  end

  private

  # 端末ごとの連番採番とハッシュチェーンの構築。
  # pos_token 行をロックして採番するため、同時会計でも欠番・重複が生じない
  # （next_receipt_sequence と同じ方式）。
  def assign_integrity_chain
    # DB(PostgreSQL)の timestamp はマイクロ秒精度のため、保存前に切り捨てておくことで
    # 「作成時に計算したハッシュ」と「DBから読み戻して再計算したハッシュ」を一致させる
    self.printed_at = printed_at.change(usec: printed_at.usec) if printed_at

    pos_token.with_lock do
      self.sequence_number = pos_token.next_journal_sequence
      pos_token.increment!(:next_journal_sequence)

      previous = JournalEntry.where(pos_token_id: pos_token.id)
                             .where.not(sequence_number: nil)
                             .order(sequence_number: :desc)
                             .first
      self.previous_hash = previous&.entry_hash || GENESIS_HASH
      self.entry_hash = compute_entry_hash
    end
  end
end
