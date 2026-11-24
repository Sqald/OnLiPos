# 客用表示。レジのカート内容を、URLを知る別画面（ブラウザ）に表示する
class CustomerDisplay < ApplicationRecord
  belongs_to :pos_token
  before_validation { self.token ||= SecureRandom.urlsafe_base64(24) }
end
