# frozen_string_literal: true

# Venda registrada pelo pequeno negócio: manual (pela conversa) ou gerada ao ganhar um card
# de pipeline de vendas. É a fonte dos indicadores diários (Painel do Dia, metas, resumo).
class Sale < ApplicationRecord
  STATUSES = %w[active cancelled].freeze
  SOURCES = %w[manual pipeline].freeze

  belongs_to :seller, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :pipeline_item, optional: true
  belongs_to :product, optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :source, inclusion: { in: SOURCES }
  validates :sold_at, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :amount, numericality: { greater_than: 0, message: :must_be_positive }, if: :manual?
  validate :seller_exists, if: -> { seller_id.present? && will_save_change_to_seller_id? }

  before_validation :default_sold_at
  before_save :sync_missing_amount

  scope :active, -> { where(status: 'active') }
  scope :cancelled, -> { where(status: 'cancelled') }
  scope :between, ->(range) { where(sold_at: range) }
  scope :on_day, ->(date) { between(Sales::TimeZone.day_range(date)) }
  scope :in_month, ->(date) { between(Sales::TimeZone.month_range(date)) }
  scope :for_seller, ->(user) { where(seller_id: user.is_a?(User) ? user.id : user) }

  def manual?
    source == 'manual'
  end

  def active?
    status == 'active'
  end

  def cancel!
    return self unless active?

    update!(status: 'cancelled', cancelled_at: Time.current)
    self
  end

  private

  def default_sold_at
    self.sold_at ||= Time.current
  end

  def seller_exists
    errors.add(:seller_id, :invalid) unless User.exists?(id: seller_id)
  end

  def sync_missing_amount
    self.missing_amount = amount.to_d.zero?
  end
end
