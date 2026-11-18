# frozen_string_literal: true

# Sends one event to the Conversions API and records it on the contact
# (additional_attributes.meta_capi.<key>) so it is never sent twice.
class MetaConversions::SendService
  BASE_URL = 'https://graph.facebook.com'
  TIMEOUT = 15

  class RetryableError < StandardError; end

  def initialize(contact:, event:, key:, event_time:, value: nil)
    @contact = contact
    @event = event.to_s
    @key = key
    @value = value
    @event_time = event_time.to_i
  end

  def perform
    return :disabled unless MetaConversions::Config.enabled?
    return :duplicate if MetaConversions::Tracker.sent?(@contact.reload, @key)

    identity = MetaConversions::Identity.new(@contact)
    return :no_identity unless identity.sendable?

    handle(post(identity))
  end

  def payload(identity)
    event = {
      event_name: event_name,
      event_time: @event_time,
      event_id: "#{@contact.id}:#{@key}",
      action_source: 'business_messaging',
      messaging_channel: 'whatsapp',
      user_data: identity.user_data
    }
    event[:custom_data] = { currency: MetaConversions::Config.currency, value: @value.to_f.round(2) } if @value.present?
    { data: [event], test_event_code: MetaConversions::Config.test_event_code }.compact
  end

  private

  def post(identity)
    response = HTTParty.post(url, body: payload(identity).to_json, headers: headers, timeout: TIMEOUT)
    raise RetryableError, "HTTP #{response.code}: #{response.body.to_s.first(300)}" if response.code == 429 || response.code >= 500

    response
  end

  def handle(response)
    body = parse(response.body)
    if response.success?
      record('sent_at' => Time.current.iso8601, 'event' => event_name, 'events_received' => body['events_received'])
      return :sent
    end

    # 4xx: the payload or the setup is wrong; retrying the same event would fail again.
    error = (body.dig('error', 'message') || response.body).to_s.first(300)
    Rails.logger.error("MetaConversions::SendService #{event_name} for contact #{@contact.id} rejected: #{error}")
    record('failed_at' => Time.current.iso8601, 'event' => event_name, 'error' => error)
    :rejected
  end

  def event_name
    MetaConversions::Config.event_name(@event)
  end

  def url
    "#{BASE_URL}/#{MetaConversions::Config.api_version}/#{MetaConversions::Config.dataset_id}/events"
  end

  def headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{MetaConversions::Config.access_token}" }
  end

  def parse(raw)
    parsed = JSON.parse(raw.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def record(entry)
    @contact.with_lock do
      attrs = (@contact.additional_attributes || {}).deep_dup
      attrs['meta_capi'] = (attrs['meta_capi'] || {}).merge(@key => entry)
      @contact.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
