# frozen_string_literal: true

# == Schema Information
#
# Table name: meta_campaigns
#
#  id               :uuid             not null, primary key
#  created_time     :datetime
#  effective_status :string
#  name             :string
#  objective        :string
#  raw              :jsonb            not null
#  status           :string
#  updated_time     :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  ad_account_id    :string           not null
#  meta_id          :string           not null
#
# Indexes
#
#  index_meta_campaigns_on_ad_account_id  (ad_account_id)
#  index_meta_campaigns_on_meta_id        (meta_id) UNIQUE
#
class MetaAds::Campaign < ApplicationRecord
  has_many :adsets, class_name: 'MetaAds::Adset', primary_key: :meta_id, foreign_key: :meta_campaign_id,
                    inverse_of: :campaign, dependent: nil
  has_many :ads, class_name: 'MetaAds::Ad', primary_key: :meta_id, foreign_key: :meta_campaign_id,
                 inverse_of: :campaign, dependent: nil
  has_many :insights, class_name: 'MetaAds::InsightDaily', primary_key: :meta_id, foreign_key: :meta_campaign_id,
                      inverse_of: :campaign, dependent: nil

  validates :meta_id, presence: true, uniqueness: true
end
