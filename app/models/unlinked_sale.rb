# frozen_string_literal: true

# A sale synced from an external CRM that could not be tied to a lead
# (no matching phone, no unique name). Feeds the review queue and the agenda
# revenue, never the lead cohort.
class UnlinkedSale < ApplicationRecord
  self.table_name = 'external_unlinked_sales'

  STATUSES = %w[pending linked created dismissed].freeze
  REASONS = %w[no_match ambiguous_name].freeze

  belongs_to :resolved_contact, class_name: 'Contact', optional: true

  validates :source, :external_id, :customer_name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :reason, inclusion: { in: REASONS }

  scope :pending, -> { where(status: 'pending') }
  scope :sold_in, ->(range) { where(sold_at: range) }

  def candidates
    Contact.where(id: candidate_contact_ids)
  end
end
