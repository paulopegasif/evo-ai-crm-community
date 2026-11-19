# frozen_string_literal: true

# Sends one synthetic event with the test event code, so the setup and the event
# names can be checked under "Test events" in Events Manager without touching
# the ad reports. Returns Meta's answer as-is.
class MetaConversions::TestEventService
  Result = Struct.new(:success, :event_name, :events_received, :message, :fbtrace_id, keyword_init: true)

  TEST_PHONE = '5511999999999'

  def initialize(event:)
    @event = MetaConversions::Integration::EVENTS.include?(event.to_s) ? event.to_s : 'lead'
  end

  def perform
    response = MetaConversions::Api.post_events([payload], test_event_code: MetaConversions::Config.test_event_code)
    body = MetaConversions::Api.parse(response.body)
    error = body['error'] || {}

    Result.new(
      success: response.success?,
      event_name: event_name,
      events_received: body['events_received'],
      message: error['error_user_msg'].presence || error['message'].presence || (response.success? ? nil : "HTTP #{response.code}"),
      fbtrace_id: body['fbtrace_id'] || error['fbtrace_id']
    )
  end

  private

  def event_name
    MetaConversions::Config.event_name(@event)
  end

  # Hashed phone + page when a page is set (the path Meta validates strictly);
  # otherwise a placeholder click id.
  def payload
    event = {
      event_name: event_name,
      event_time: Time.current.to_i,
      event_id: "test:#{SecureRandom.hex(6)}",
      action_source: 'business_messaging',
      messaging_channel: 'whatsapp',
      user_data: user_data
    }
    event[:custom_data] = { currency: MetaConversions::Config.currency, value: 1.0 } if @event == 'purchase'
    event
  end

  def user_data
    data = { whatsapp_business_account_id: MetaConversions::Config.waba_id }
    page_id = MetaConversions::Config.page_id
    return data.merge(page_id: page_id, ph: [Digest::SHA256.hexdigest(TEST_PHONE)]) if page_id.present?

    data.merge(ctwa_clid: "TEST_#{SecureRandom.hex(16)}")
  end
end
