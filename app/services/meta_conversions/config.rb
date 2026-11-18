# frozen_string_literal: true

# Settings of the Conversions API for Business Messaging (Click-to-WhatsApp ads).
# https://developers.facebook.com/documentation/ads-commerce/conversions-api/business-messaging
#
# Off unless META_CAPI_ENABLED=true and the dataset, token and WhatsApp Business
# Account id are set. The token needs whatsapp_business_management and
# whatsapp_business_manage_events on that WhatsApp Business Account.
module MetaConversions::Config
  module_function

  DEFAULT_EVENT_NAMES = { 'lead' => 'LeadSubmitted', 'qualified' => 'QualifiedLead', 'purchase' => 'Purchase' }.freeze

  def enabled?
    ActiveModel::Type::Boolean.new.cast(env('META_CAPI_ENABLED')) == true &&
      dataset_id.present? && access_token.present? && waba_id.present?
  end

  def dataset_id
    env('META_CAPI_DATASET_ID')
  end

  def access_token
    env('META_CAPI_ACCESS_TOKEN')
  end

  def waba_id
    env('META_CAPI_WABA_ID')
  end

  # Optional. Needed only to send events without a ctwa_clid (hashed phone matching).
  def page_id
    env('META_CAPI_PAGE_ID')
  end

  # Optional. Events sent with it show up under "Test events" in Events Manager only.
  def test_event_code
    env('META_CAPI_TEST_EVENT_CODE')
  end

  def api_version
    env('META_CAPI_API_VERSION') || MetaAds::GraphClient::DEFAULT_VERSION
  end

  def currency
    env('META_CAPI_CURRENCY') || 'BRL'
  end

  # Leads older than this never produce events (history synced from the source CRM).
  def max_lead_age
    (env('META_CAPI_MAX_LEAD_AGE_DAYS') || 90).to_i.days
  end

  # e.g. META_CAPI_EVENT_QUALIFIED=Schedule
  def event_name(event)
    env("META_CAPI_EVENT_#{event.to_s.upcase}") || DEFAULT_EVENT_NAMES.fetch(event.to_s)
  end

  def env(key)
    ENV.fetch(key, nil).presence
  end
end
