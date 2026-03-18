class Provisioning < ApplicationRecord
  belongs_to :user
  belongs_to :store
  has_many :pos_tokens, dependent: :nullify
  
  validates :name, presence: true
  validates :store_context, presence: true
  validates :hardware_settings, presence: true
end
