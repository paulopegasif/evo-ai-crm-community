# Numbers onboarded through Embedded Signup with a new phone are verified but
# not yet registered for Cloud API (platform_type NOT_APPLICABLE), and Tech
# Providers must register them before they can send messages. Numbers already
# on Cloud API (including coexistence onboarding) are left untouched.
# ref https://developers.facebook.com/docs/whatsapp/cloud-api/reference/registration
class Whatsapp::PhoneNumberRegistrationService
  GRAPH_URL = 'https://graph.facebook.com/v23.0'.freeze

  pattr_initialize [:channel!]

  def perform
    return unless eligible? && unregistered?

    pin = format('%06d', SecureRandom.random_number(1_000_000))
    return unless register(pin)

    # update_columns skips the provider_config change callback (re-subscribe)
    channel.update_columns(provider_config: channel.provider_config.merge('two_step_pin' => pin)) # rubocop:disable Rails/SkipsModelValidations
    Rails.logger.info "WhatsApp register: registered phone #{phone_number_id}"
  rescue StandardError => e
    Rails.logger.error "WhatsApp register error: #{e.inspect}"
  end

  private

  # In Hub mode the Hub owns the Meta app token and onboarding.
  def eligible?
    channel.provider == 'whatsapp_cloud' && !MetaBaseUrl.enabled? && phone_number_id.present? && api_key.present?
  end

  def phone_number_id
    channel.provider_config['phone_number_id']
  end

  def api_key
    channel.provider_config['api_key']
  end

  def headers
    { 'Authorization' => "Bearer #{api_key}", 'Content-Type' => 'application/json' }
  end

  def unregistered?
    response = HTTParty.get("#{GRAPH_URL}/#{phone_number_id}", query: { fields: 'platform_type' }, headers: headers)
    response.success? && response.parsed_response['platform_type'] == 'NOT_APPLICABLE'
  end

  def register(pin)
    response = HTTParty.post(
      "#{GRAPH_URL}/#{phone_number_id}/register",
      headers: headers,
      body: { messaging_product: 'whatsapp', pin: pin }.to_json
    )
    return true if response.success?

    Rails.logger.error "WhatsApp register: failed for phone #{phone_number_id}: #{response.code} - #{response.body}"
    false
  end
end
