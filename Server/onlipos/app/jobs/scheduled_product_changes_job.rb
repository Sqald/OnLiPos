# 適用日が来た価格・税率の変更を反映する
class ScheduledProductChangesJob < ApplicationJob
  def perform
    ScheduledProductChange.apply_due!
  end
end
