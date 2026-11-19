# frozen_string_literal: true

# State of the (single) Conversions API integration, persisted in the
# `meta_conversions` Integrations::Hook settings and managed from the
# integrations page. The access token is stored encrypted, or borrowed from the
# Meta Ads integration when the same System User token carries both sets of
# permissions (token_source = 'meta_ads').
class MetaConversions::Integration
  APP_ID = 'meta_conversions'
  TOKEN_SOURCES = %w[own meta_ads].freeze
  EVENTS = %w[lead qualified purchase].freeze
  STATUS_CONNECTED = 'connected'
  STATUS_ERROR = 'error'

  def self.current
    hook = Integrations::Hook.find_by(app_id: APP_ID)
    hook ? new(hook) : nil
  end

  def self.find_or_initialize
    new(Integrations::Hook.find_or_initialize_by(app_id: APP_ID))
  end

  def self.empty_json
    new(Integrations::Hook.new(app_id: APP_ID)).as_json
  end

  attr_reader :hook

  def initialize(hook)
    @hook = hook
  end

  def settings
    (hook.settings || {}).with_indifferent_access
  end

  def configured?
    hook.persisted?
  end

  def enabled?
    configured? && settings[:enabled] == true
  end

  # Turned on and complete enough to send events.
  def ready?
    enabled? && dataset_id.present? && waba_id.present? && access_token.present?
  end

  def waba_id
    settings[:waba_id].presence
  end

  def page_id
    settings[:page_id].presence
  end

  def dataset_id
    settings[:dataset_id].presence
  end

  def test_event_code
    settings[:test_event_code].presence
  end

  def token_source
    TOKEN_SOURCES.include?(settings[:token_source]) ? settings[:token_source] : 'own'
  end

  def access_token
    return MetaAds::Integration.current&.access_token if token_source == 'meta_ads'

    MetaAds::Credentials.decrypt(settings[:access_token_encrypted])
  end

  # Custom event name for 'lead' / 'qualified' / 'purchase', or nil for the default.
  def event_name(event)
    settings.dig(:event_names, event.to_s).presence
  end

  # Merges keys into the hook settings under a row lock.
  def write!(attributes)
    attributes = attributes.deep_stringify_keys
    if hook.persisted?
      hook.with_lock do
        hook.settings = (hook.settings || {}).merge(attributes)
        hook.save!
      end
    else
      hook.settings = (hook.settings || {}).merge(attributes)
      hook.save!
    end
  end

  def record_error!(error)
    write!('connection_status' => STATUS_ERROR,
           'last_error' => { 'message' => error.message, 'code' => error.try(:code), 'at' => Time.current.iso8601 })
  end

  def as_json(*)
    s = settings
    {
      configured: configured?,
      enabled: enabled?,
      waba_id: s[:waba_id],
      waba_name: s[:waba_name],
      page_id: s[:page_id],
      dataset_id: s[:dataset_id],
      token_source: token_source,
      token_hint: token_hint,
      meta_ads_token_available: MetaAds::Integration.current&.access_token.present? || false,
      test_event_code: s[:test_event_code],
      event_names: MetaConversions::Config::DEFAULT_EVENT_NAMES.merge((s[:event_names] || {}).compact_blank),
      default_event_names: MetaConversions::Config::DEFAULT_EVENT_NAMES,
      connection_status: connection_status,
      last_error: s[:last_error],
      connected_at: s[:connected_at],
      stats: configured? ? MetaConversions::Stats.call : nil
    }
  end

  private

  def token_hint
    return MetaAds::Integration.current&.settings&.dig(:token_hint) if token_source == 'meta_ads'

    settings[:token_hint]
  end

  def connection_status
    return 'not_configured' unless configured?

    settings[:connection_status].presence || STATUS_CONNECTED
  end
end
