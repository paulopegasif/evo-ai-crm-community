# frozen_string_literal: true

# Imports the ad account structure (campaigns, ad sets, ads — including paused
# and archived) and daily ad-level insights into the local meta_* tables.
# Idempotent: rows are upserted by Meta id (insights by ad + date).
#
# After the recent window, each run also fills one older block of history (newest
# first) until HISTORY_DAYS are covered. The cursor lives in the integration
# settings and only moves once a block is stored, so a failed run retries it.
class MetaAds::SyncService
  INITIAL_HISTORY_DAYS = 90
  # Meta keeps revising recent days (late attribution, billing adjustments).
  REFRESH_DAYS = 7
  INSIGHTS_WINDOW_DAYS = 30
  HISTORY_DAYS = 730
  HISTORY_CHUNK_DAYS = 90
  # Bump when insight fields change so stored days are imported again.
  HISTORY_VERSION = 2
  PAGE_LIMIT = 500
  UPSERT_BATCH = 500

  CAMPAIGN_FIELDS = 'id,name,status,effective_status,objective,created_time,updated_time'
  ADSET_FIELDS = 'id,name,status,effective_status,campaign_id'
  AD_FIELDS = 'id,name,status,effective_status,adset_id,campaign_id'
  INSIGHT_FIELDS = 'ad_id,campaign_id,spend,impressions,reach,clicks,actions,date_start'
  # Result columns => Meta action types, first match wins.
  RESULT_ACTIONS = {
    conversations: %w[onsite_conversion.messaging_conversation_started_7d],
    meta_leads: %w[lead onsite_conversion.lead_grouped],
    link_clicks: %w[link_click]
  }.freeze
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
    insight_rows = sync_insights(insights_range)
    history_rows = sync_history

    { campaigns: campaigns, adsets: adsets, ads: ads, insight_rows: insight_rows + history_rows }
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

  def sync_insights(range)
    count = 0
    range.step(INSIGHTS_WINDOW_DAYS).each do |window_start|
      window_end = [window_start + (INSIGHTS_WINDOW_DAYS - 1).days, range.end].min
      count += sync_insights_window(window_start, window_end)
    end
    count
  end

  def sync_history
    cursor = history_cursor
    floor = today - HISTORY_DAYS.days
    return 0 if cursor <= floor

    from = [cursor - HISTORY_CHUNK_DAYS.days, floor].max
    count = sync_insights(from..(cursor - 1.day))
    @integration.write!('history_synced_from' => from.iso8601, 'history_version' => HISTORY_VERSION)
    count
  end

  # Oldest day already stored with the current fields. Without a cursor for this
  # version, only the window imported in this run counts as covered.
  def history_cursor
    settings = @integration.settings
    if settings[:history_version].to_i == HISTORY_VERSION && settings[:history_synced_from].present?
      Date.iso8601(settings[:history_synced_from])
    else
      insights_range.begin
    end
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
      currency: @integration.settings[:currency],
      actions: row['actions'] || [],
      **result_attributes(row['actions'])
    }
  end

  def result_attributes(actions)
    values = Array(actions).to_h { |action| [action['action_type'], action['value'].to_i] }
    RESULT_ACTIONS.transform_values { |types| values.values_at(*types).compact.first || 0 }
  end
end
