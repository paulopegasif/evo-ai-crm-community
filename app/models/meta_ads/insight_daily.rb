# frozen_string_literal: true

# == Schema Information
#
# Table name: meta_ad_insights_daily
#
#  id               :uuid             not null, primary key
#  clicks           :bigint           default(0), not null
#  currency         :string
#  date             :date             not null
#  impressions      :bigint           default(0), not null
#  reach            :bigint           default(0), not null
#  spend            :decimal(14, 2)   default(0.0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  meta_ad_id       :string           not null
#  meta_campaign_id :string
#
# Indexes
#
#  index_meta_ad_insights_daily_on_meta_ad_id_and_date        (meta_ad_id,date) UNIQUE
#  index_meta_ad_insights_daily_on_meta_campaign_id_and_date  (meta_campaign_id,date)
#
class MetaAds::InsightDaily < ApplicationRecord
  self.table_name = 'meta_ad_insights_daily'

  belongs_to :ad, class_name: 'MetaAds::Ad', primary_key: :meta_id, foreign_key: :meta_ad_id,
                  optional: true, inverse_of: :insights
  belongs_to :campaign, class_name: 'MetaAds::Campaign', primary_key: :meta_id, foreign_key: :meta_campaign_id,
                        optional: true, inverse_of: :insights

  validates :meta_ad_id, :date, presence: true
end
