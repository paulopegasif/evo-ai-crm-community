# frozen_string_literal: true

# Meta mensal de faturamento. user_id nulo = meta geral da empresa.
class SalesGoal < ApplicationRecord
  belongs_to :user, optional: true

  validates :month, presence: true
  validates :amount, numericality: { greater_than: 0 }
  validates :user_id, uniqueness: { scope: :month }

  before_validation :normalize_month

  scope :general, -> { where(user_id: nil) }
  scope :for_month, ->(date) { where(month: date.to_date.beginning_of_month) }

  private

  def normalize_month
    self.month = month&.beginning_of_month
  end
end
