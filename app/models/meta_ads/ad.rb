# frozen_string_literal: true

# == Schema Information
#
# Table name: meta_ads
#
#  id               :uuid             not null, primary key
#  effective_status :string
#  name             :string
#  raw              :jsonb            not null
#  status           :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  meta_adset_id    :string
#  meta_campaign_id :string
#  meta_id          :string           not null
#
# Indexes
#
#  index_meta_ads_on_meta_adset_id     (meta_adset_id)
#  index_meta_ads_on_meta_campaign_id  (meta_campaign_id)
#  index_meta_ads_on_meta_id           (meta_id) UNIQUE
#
class MetaAds::Ad < ApplicationRecord
  belongs_to :campaign, class_name: 'MetaAds::Campaign', primary_key: :meta_id, foreign_key: :meta_campaign_id,
                        optional: true, inverse_of: :ads
  belongs_to :adset, class_name: 'MetaAds::Adset', primary_key: :meta_id, foreign_key: :meta_adset_id,
                     optional: true, inverse_of: :ads
  has_many :insights, class_name: 'MetaAds::InsightDaily', primary_key: :meta_id, foreign_key: :meta_ad_id,
                      inverse_of: :ad, dependent: nil

  validates :meta_id, presence: true, uniqueness: true
end
