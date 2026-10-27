# frozen_string_literal: true

# Imports the ad account structure (campaigns, ad sets, ads — including paused
# and archived) and daily ad-level insights into the local meta_* tables.
# Idempotent: rows are upserted by Meta id (insights by ad + date).
class MetaAds::SyncService
  INITIAL_HISTORY_DAYS = 90
  # Meta keeps revising recent days (late attribution, billing adjustments).
  REFRESH_DAYS = 7
  INSIGHTS_WINDOW_DAYS = 30
  PAGE_LIMIT = 500
  UPSERT_BATCH = 500

  CAMPAIGN_FIELDS = 'id,name,status,effective_status,objective,created_time,updated_time'
  ADSET_FIELDS = 'id,name,status,effective_status,campaign_id'
  AD_FIELDS = 'id,name,status,effective_status,adset_id,campaign_id'
  INSIGHT_FIELDS = 'ad_id,campaign_id,spend,impressions,reach,clicks,date_start'
  # Valid effective_status values per object; without an explicit filter the Graph API
  # omits archived/deleted objects.
  BASE_STATUSES = %w[ACTIVE PAUSED DELETED ARCHIVED IN_PROCESS WITH_ISSUES].freeze
  EFFECTIVE_STATUSES = {
    'campaigns' => BASE_STATUSES,
    'adsets' => BASE_STATUSES + %w[CAMPAIGN_PAUSED],
    'ads' => BASE_STATUSES + %w[CAMPAIGN_PAUSED ADSET_PAUSED PENDING_REVIEW DISAPPROVED PREAPPROVED PENDING_BILLING_INFO]
  }.freeze

  def initialize(integration:, client: nil, today: nil)
    @integration = integration
    @account_id = integration.ad_account_id
    @client = client || MetaAds::GraphClient.new(access_token: integration.access_token)
    @today = today
  end

  def perform
    campaigns = sync_objects('campaigns', CAMPAIGN_FIELDS, MetaAds::Campaign) { |row| campaign_attributes(row) }
    adsets = sync_objects('adsets', ADSET_FIELDS, MetaAds::Adset) { |row| adset_attributes(row) }
    ads = sync_objects('ads', AD_FIELDS, MetaAds::Ad) { |row| ad_attributes(row) }
    insight_rows = sync_insights

    { campaigns: campaigns, adsets: adsets, ads: ads, insight_rows: insight_rows }
  end

  def insights_range
    from = @integration.never_synced? ? today - INITIAL_HISTORY_DAYS.days : today - REFRESH_DAYS.days
    from..today
  end

  private

  def today
    @today ||= begin
      zone = ActiveSupport::TimeZone[@integration.settings[:timezone_name].to_s]
      zone ? Time.current.in_time_zone(zone).to_date : Date.current
    end
  end

  def sync_objects(edge, fields, model)
    count = 0
    batch = []
    params = { fields: fields, limit: PAGE_LIMIT, filtering: status_filter(edge).to_json }

    @client.each_page_item("#{@account_id}/#{edge}", params) do |row|
      batch << yield(row).merge(raw: row)
      count += 1
      flush(model, batch, :meta_id) if batch.size >= UPSERT_BATCH
    end
    flush(model, batch, :meta_id)
    count
  end

  def status_filter(edge)
    [{ field: "#{edge.delete_suffix('s')}.effective_status", operator: 'IN', value: EFFECTIVE_STATUSES.fetch(edge) }]
  end

  def sync_insights
    count = 0
    insights_range.step(INSIGHTS_WINDOW_DAYS).each do |window_start|
      window_end = [window_start + (INSIGHTS_WINDOW_DAYS - 1).days, insights_range.end].min
      count += sync_insights_window(window_start, window_end)
    end
    count
  end

  def sync_insights_window(since, until_date)
    batch = []
    count = 0
    params = {
      level: 'ad',
      time_increment: 1,
      fields: INSIGHT_FIELDS,
      limit: PAGE_LIMIT,
      time_range: { since: since.iso8601, until: until_date.iso8601 }.to_json
    }

    @client.each_page_item("#{@account_id}/insights", params) do |row|
      batch << insight_attributes(row)
      count += 1
      flush(MetaAds::InsightDaily, batch, %i[meta_ad_id date]) if batch.size >= UPSERT_BATCH
    end
    flush(MetaAds::InsightDaily, batch, %i[meta_ad_id date])
    count
  end

  def flush(model, batch, unique_by)
    return if batch.empty?

    # upsert_all fills created_at/updated_at itself (record_timestamps).
    model.upsert_all(batch, unique_by: unique_by, update_only: batch.first.keys - Array(unique_by)) # rubocop:disable Rails/SkipsModelValidations
    batch.clear
  end

  def campaign_attributes(row)
    {
      meta_id: row['id'],
      ad_account_id: @account_id,
      name: row['name'],
      status: row['status'],
      effective_status: row['effective_status'],
      objective: row['objective'],
      created_time: row['created_time'],
      updated_time: row['updated_time']
    }
  end

  def adset_attributes(row)
    {
      meta_id: row['id'],
      meta_campaign_id: row['campaign_id'],
      name: row['name'],
      status: row['status'],
      effective_status: row['effective_status']
    }
  end

  def ad_attributes(row)
    {
      meta_id: row['id'],
      meta_adset_id: row['adset_id'],
      meta_campaign_id: row['campaign_id'],
      name: row['name'],
      status: row['status'],
      effective_status: row['effective_status']
    }
  end

  def insight_attributes(row)
    {
      meta_ad_id: row['ad_id'],
      meta_campaign_id: row['campaign_id'],
      date: row['date_start'],
      spend: row['spend'].to_d,
      impressions: row['impressions'].to_i,
      reach: row['reach'].to_i,
      clicks: row['clicks'].to_i,
      currency: @integration.settings[:currency]
    }
  end
end
