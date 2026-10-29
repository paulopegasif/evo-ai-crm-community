# frozen_string_literal: true

class ExternalLink < ApplicationRecord
  belongs_to :record, polymorphic: true

  validates :source, presence: true
  validates :external_type, presence: true
  validates :external_id, presence: true, uniqueness: { scope: %i[source external_type] }
  validates :record_type, presence: true
  validates :record_id, presence: true
end
