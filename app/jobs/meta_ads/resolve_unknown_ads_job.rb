# frozen_string_literal: true

# Leads can point to ads outside the synced catalog (older or paused ads the
# account sync never listed). Looks them up by id so their campaign is known;
# ads Meta does not return are stored as UNAVAILABLE and never retried.
class MetaAds::ResolveUnknownAdsJob < ApplicationJob
  queue_as :scheduled_jobs

  FIELDS = 'id,name,status,effective_status,adset{id,name},campaign{id,name,status,effective_status,objective}'
  BATCH = 50

  def perform
    integration = MetaAds::Integration.current
    return unless integration&.syncable?

    client = MetaAds::GraphClient.new(access_token: integration.access_token)
    unknown_ad_ids.first(BATCH).each { |ad_id| resolve(client, integration, ad_id) }
  rescue MetaAds::GraphClient::TokenInvalidError, MetaAds::GraphClient::RateLimitedError => e
    Rails.logger.warn("MetaAds::ResolveUnknownAdsJob stopped: #{e.message}")
  end

  private

  def unknown_ad_ids
    Contact.where("additional_attributes ? 'ad_id'")
           .where("NOT EXISTS (SELECT 1 FROM meta_ads WHERE meta_ads.meta_id = contacts.additional_attributes->>'ad_id')")
           .distinct.pluck(Arel.sql("contacts.additional_attributes->>'ad_id'"))
           .grep(/\A\d+\z/)
  end

  def resolve(client, integration, ad_id)
    row = client.get(ad_id, fields: FIELDS)
    store(row, integration)
  rescue MetaAds::GraphClient::ApiError => e
    Rails.logger.info("MetaAds::ResolveUnknownAdsJob ad #{ad_id} unavailable: #{e.message}")
    MetaAds::Ad.create!(meta_id: ad_id, name: nil, effective_status: MetaAds::Ad::UNAVAILABLE)
  end

  def store(row, integration)
    campaign = row['campaign'] || {}
    adset = row['adset'] || {}
    if campaign['id'].present?
      MetaAds::Campaign.find_or_initialize_by(meta_id: campaign['id']).tap do |c|
        c.ad_account_id ||= integration.ad_account_id
        c.name = campaign['name']
        c.status ||= campaign['status']
        c.effective_status ||= campaign['effective_status']
        c.objective ||= campaign['objective']
        c.save!
      end
    end
    if adset['id'].present?
      MetaAds::Adset.find_or_initialize_by(meta_id: adset['id']).tap do |a|
        a.meta_campaign_id ||= campaign['id']
        a.name = adset['name']
        a.save!
      end
    end
    MetaAds::Ad.find_or_initialize_by(meta_id: row['id']).update!(
      name: row['name'], status: row['status'], effective_status: row['effective_status'],
      meta_adset_id: adset['id'], meta_campaign_id: campaign['id']
    )
  end
end
