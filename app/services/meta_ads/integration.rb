# frozen_string_literal: true

# State of the (single) Meta Ads integration, persisted in the `meta_ads`
# Integrations::Hook settings. Wraps reads/writes so the controller and the sync
# job share the same rules (token encryption, status values, safe merges).
class MetaAds::Integration
  APP_ID = 'meta_ads'
  STATUS_CONNECTED = 'connected'
  STATUS_ERROR = 'error'
  STATUS_TOKEN_INVALID = 'token_invalid'

  def self.current
    hook = Integrations::Hook.find_by(app_id: APP_ID)
    hook ? new(hook) : nil
  end

  # Creates or updates the hook after the credentials were validated.
  def self.connect!(ad_account_id:, access_token:, account:)
    hook = Integrations::Hook.find_or_initialize_by(app_id: APP_ID)
    integration = new(hook)
    account_changed = hook.settings.to_h['ad_account_id'].present? && hook.settings.to_h['ad_account_id'] != ad_account_id

    integration.write!(
      'ad_account_id' => ad_account_id,
      'access_token_encrypted' => MetaAds::Credentials.encrypt(access_token),
      'token_hint' => MetaAds::Credentials.hint(access_token),
      'account_name' => account.account_name,
      'currency' => account.currency,
      'timezone_name' => account.timezone_name,
      'connection_status' => STATUS_CONNECTED,
      'last_error' => nil,
      # A different ad account starts over with a full history import.
      **(account_changed ? { 'last_synced_at' => nil } : {})
    )
    integration
  end

  attr_reader :hook

  def initialize(hook)
    @hook = hook
  end

  def settings
    (hook.settings || {}).with_indifferent_access
  end

  def ad_account_id
    settings[:ad_account_id]
  end

  def access_token
    MetaAds::Credentials.decrypt(settings[:access_token_encrypted])
  end

  def connection_status
    settings[:connection_status].presence || STATUS_CONNECTED
  end

  # Automatic syncs stop once the token is known to be invalid, until reconfigured.
  def syncable?
    hook.persisted? && ad_account_id.present? && access_token.present? && connection_status != STATUS_TOKEN_INVALID
  end

  def never_synced?
    settings[:last_synced_at].blank?
  end

  # Merges keys into the hook settings, re-reading the row under a lock so the
  # controller and the sync job never clobber each other's keys.
  def write!(attributes)
    if hook.persisted?
      hook.with_lock do
        hook.settings = (hook.settings || {}).merge(attributes.stringify_keys)
        hook.save!
      end
    else
      hook.settings = (hook.settings || {}).merge(attributes.stringify_keys)
      hook.save!
    end
  end

  def record_error!(error, status: STATUS_ERROR)
    write!(
      'connection_status' => status,
      'last_error' => { 'message' => error.message, 'code' => error.try(:code), 'at' => Time.current.iso8601 }
    )
  end

  def as_json(*)
    s = settings
    {
      configured: hook.persisted?,
      ad_account_id: s[:ad_account_id],
      token_hint: s[:token_hint],
      account_name: s[:account_name],
      currency: s[:currency],
      timezone_name: s[:timezone_name],
      connection_status: hook.persisted? ? connection_status : 'not_configured',
      last_synced_at: s[:last_synced_at],
      last_sync_started_at: s[:last_sync_started_at],
      last_error: s[:last_error],
      sync_in_progress: MetaAds::SyncLock.locked?,
      counts: s[:counts] || { 'campaigns' => 0, 'adsets' => 0, 'ads' => 0 },
      graph_api_version: MetaAds::GraphClient.new(access_token: nil).version
    }
  end

  # Payload for the integration page when no hook exists yet.
  def self.empty_json
    new(Integrations::Hook.new(app_id: APP_ID)).as_json
  end
end
