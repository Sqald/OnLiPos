# 商品CSVの一括取込を非同期で行うジョブ
class ProductImportJob < ApplicationJob
  queue_as :default

  def perform(import)
    import.run! if import.queued?
  end
end
