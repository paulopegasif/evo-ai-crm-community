# frozen_string_literal: true

# Scheduled hourly (config/schedule.yml) and enqueued by "Sincronizar agora".
class MetaAds::SyncJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    integration = MetaAds::Integration.current
    return unless integration&.syncable?
    return unless MetaAds::SyncLock.acquire

    begin
      run(integration)
    ensure
      MetaAds::SyncLock.release
    end
  end

  private

  def run(integration)
    integration.write!('last_sync_started_at' => Time.current.iso8601)
    MetaAds::SyncService.new(integration: integration).perform

    integration.write!(
      'connection_status' => MetaAds::Integration::STATUS_CONNECTED,
      'last_synced_at' => Time.current.iso8601,
      'last_error' => nil,
      'counts' => current_counts(integration.ad_account_id)
    )
  rescue MetaAds::GraphClient::TokenInvalidError => e
    integration.record_error!(e, status: MetaAds::Integration::STATUS_TOKEN_INVALID)
  rescue MetaAds::GraphClient::RateLimitedError => e
    # Keep the connection usable; the next scheduled run resumes.
    integration.record_error!(e, status: MetaAds::Integration::STATUS_CONNECTED)
  rescue MetaAds::GraphClient::Error => e
    integration.record_error!(e)
  end

  def current_counts(ad_account_id)
    campaign_ids = MetaAds::Campaign.where(ad_account_id: ad_account_id).select(:meta_id)
    {
      'campaigns' => MetaAds::Campaign.where(ad_account_id: ad_account_id).count,
      'adsets' => MetaAds::Adset.where(meta_campaign_id: campaign_ids).count,
      'ads' => MetaAds::Ad.where(meta_campaign_id: campaign_ids).count
    }
  end
end
