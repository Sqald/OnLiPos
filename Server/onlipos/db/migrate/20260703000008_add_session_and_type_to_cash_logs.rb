# cash_logs を「金種実査の記録」に純化するための追加。
# - log_type: is_start/is_pickup/is_end のブール組み合わせを単一の種別に整理
#   （0: open, 1: check, 2: pickup(旧方式・互換用), 3: close）
# - register_session: 実査がどのレジセッションに属するかを明示
# - expected_amount / diff_amount: 実査時点の理論在高と過不足を確定保存
#   （現状はレスポンスで計算するだけで保存されず、後から検証できない）
class AddSessionAndTypeToCashLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :cash_logs, :log_type, :integer, null: false, default: 1
    add_reference :cash_logs, :register_session, foreign_key: true
    add_column :cash_logs, :expected_amount, :integer
    add_column :cash_logs, :diff_amount, :integer

    add_index :cash_logs, [ :pos_token_id, :open_date, :log_type ]

    # 既存行の種別をブールフラグから補完（フラグ自体は互換のため残す）
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE cash_logs
          SET log_type = CASE
            WHEN is_start  THEN 0
            WHEN is_pickup THEN 2
            WHEN is_end    THEN 3
            ELSE 1
          END
        SQL
      end
    end
  end
end
