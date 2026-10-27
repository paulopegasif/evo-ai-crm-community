# frozen_string_literal: true

# Persists where a lead came from on the contact's additional_attributes.
#
# First-touch keys (utm_*, ad_*, ctwa_clid, fbclid, attributed_at) are written once,
# the first time an identifiable source shows up, and never overwritten afterwards.
# Every identifiable touch refreshes `last_touch`.
#
#   Attribution::RecordService.new(contact: contact, source: :whatsapp_referral, touch: referral).perform
#   Attribution::RecordService.new(contact: contact, source: :public_api, touch: metadata).perform
class Attribution::RecordService
  UTM_KEYS = %w[utm_source utm_medium utm_campaign utm_content utm_term fbclid].freeze
  TOUCH_KEYS = (UTM_KEYS + %w[ad_id ad_source_type ad_source_url ad_headline ctwa_clid]).freeze
  # Presence of any of these means the contact already has a first-touch origin.
  FIRST_TOUCH_MARKERS = %w[utm_source ad_id].freeze
  MAX_VALUE_LENGTH = 500

  def initialize(contact:, touch:, source:)
    @contact = contact
    @touch = touch.respond_to?(:to_unsafe_h) ? touch.to_unsafe_h : touch.to_h
    @source = source.to_sym
  end

  def perform
    return false if @contact.blank?

    attributes = normalized_touch
    return false if attributes.blank?

    @contact.with_lock do
      current = (@contact.additional_attributes || {}).deep_dup
      now = Time.current.iso8601

      if first_touch_missing?(current)
        current.merge!(attributes)
        current['attribution_channel'] = @source.to_s
        current['attributed_at'] = now
      end

      current['last_touch'] = attributes.merge('attribution_channel' => @source.to_s, 'attributed_at' => now)

      @contact.update_columns(additional_attributes: current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    end
    true
  end

  private

  def normalized_touch
    raw = @source == :whatsapp_referral ? referral_touch : utm_touch
    raw.transform_values { |value| value.to_s.strip.first(MAX_VALUE_LENGTH) }
       .select { |key, value| TOUCH_KEYS.include?(key) && value.present? }
  end

  # WhatsApp Cloud API `messages[].referral`:
  # https://developers.facebook.com/docs/whatsapp/cloud-api/webhooks/payload-examples#received-message-triggered-by-click-to-whatsapp-ads
  def referral_touch
    referral = @touch.stringify_keys
    return {} if referral['source_id'].blank? && referral['ctwa_clid'].blank?

    source_type = referral['source_type'].to_s.downcase
    {
      'utm_source' => 'meta_ads',
      'utm_medium' => source_type == 'post' ? 'social' : 'paid_social',
      'ad_id' => referral['source_id'],
      'ad_source_type' => source_type,
      'ad_source_url' => referral['source_url'],
      'ad_headline' => referral['headline'],
      'ctwa_clid' => referral['ctwa_clid']
    }
  end

  def utm_touch
    @touch.stringify_keys.slice(*UTM_KEYS)
  end

  def first_touch_missing?(attributes)
    FIRST_TOUCH_MARKERS.none? { |key| attributes[key].present? }
  end
end
