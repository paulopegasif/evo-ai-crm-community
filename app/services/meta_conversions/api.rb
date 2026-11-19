# frozen_string_literal: true

# POST /{dataset_id}/events with the configured dataset and token.
module MetaConversions::Api
  module_function

  BASE_URL = 'https://graph.facebook.com'
  TIMEOUT = 15

  def post_events(events, test_event_code: MetaConversions::Config.test_event_code)
    body = { data: events, test_event_code: test_event_code }.compact
    HTTParty.post(url, body: body.to_json, headers: headers, timeout: TIMEOUT)
  end

  def parse(raw)
    parsed = JSON.parse(raw.to_s)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def url
    "#{BASE_URL}/#{MetaConversions::Config.api_version}/#{MetaConversions::Config.dataset_id}/events"
  end

  def headers
    { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{MetaConversions::Config.access_token}" }
  end
end
