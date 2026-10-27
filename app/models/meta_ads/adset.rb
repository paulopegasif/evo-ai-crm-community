# frozen_string_literal: true

# == Schema Information
#
# Table name: meta_adsets
#
#  id               :uuid             not null, primary key
#  effective_status :string
#  name             :string
#  raw              :jsonb            not null
#  status           :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  meta_campaign_id :string
#  meta_id          :string           not null
#
# Indexes
#
#  index_meta_adsets_on_meta_campaign_id  (meta_campaign_id)
#  index_meta_adsets_on_meta_id           (meta_id) UNIQUE
#
class MetaAds::Adset < ApplicationRecord
  belongs_to :campaign, class_name: 'MetaAds::Campaign', primary_key: :meta_id, foreign_key: :meta_campaign_id,
                        optional: true, inverse_of: :adsets
  has_many :ads, class_name: 'MetaAds::Ad', primary_key: :meta_id, foreign_key: :meta_adset_id,
                 inverse_of: :adset, dependent: nil

  validates :meta_id, presence: true, uniqueness: true
end
