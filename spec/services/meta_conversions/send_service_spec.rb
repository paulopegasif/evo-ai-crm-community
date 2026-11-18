# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe MetaConversions::SendService do
  let(:settings) do
    { 'META_CAPI_ENABLED' => 'true', 'META_CAPI_DATASET_ID' => '111', 'META_CAPI_ACCESS_TOKEN' => 'tok',
      'META_CAPI_WABA_ID' => '222', 'META_CAPI_API_VERSION' => 'v27.0' }
  end
  let(:contact) do
    Contact.create!(name: 'Lead Anúncio', phone_number: '+5561985702132', additional_attributes: { 'ctwa_clid' => 'ARAk-click' })
  end
  let(:url) { 'https://graph.facebook.com/v27.0/111/events' }
  let(:service) { described_class.new(contact: contact, event: 'purchase', key: 'purchase:1', value: 1200, event_time: 1_763_000_000) }

  before { allow(MetaConversions::Config).to receive(:env) { |key| settings[key] } }

  it 'sends a business messaging event with the click id and records it' do
    stub = stub_request(:post, url).with(
      headers: { 'Authorization' => 'Bearer tok' },
      body: {
        data: [{
          event_name: 'Purchase', event_time: 1_763_000_000, event_id: "#{contact.id}:purchase:1",
          action_source: 'business_messaging', messaging_channel: 'whatsapp',
          user_data: { whatsapp_business_account_id: '222', ctwa_clid: 'ARAk-click' },
          custom_data: { currency: 'BRL', value: 1200.0 }
        }]
      }.to_json
    ).to_return(status: 200, body: { events_received: 1 }.to_json, headers: { 'Content-Type' => 'application/json' })

    expect(service.perform).to eq(:sent)
    expect(stub).to have_been_requested
    expect(contact.reload.additional_attributes.dig('meta_capi', 'purchase:1', 'sent_at')).to be_present
    expect(service.perform).to eq(:duplicate)
  end

  it 'falls back to the hashed phone and page id without a click id' do
    settings['META_CAPI_PAGE_ID'] = '333'
    contact.update_columns(additional_attributes: {}) # rubocop:disable Rails/SkipsModelValidations
    hashed = Digest::SHA256.hexdigest(contact.reload.phone_number.delete('+'))
    expected = { 'whatsapp_business_account_id' => '222', 'page_id' => '333', 'ph' => [hashed] }
    stub_request(:post, url).with { |req| JSON.parse(req.body)['data'][0]['user_data'] == expected }
                            .to_return(status: 200, body: '{"events_received":1}') # no JSON content type on purpose
    expect(service.perform).to eq(:sent)
  end

  it 'records a rejected event without retrying' do
    stub_request(:post, url).to_return(status: 400, body: { error: { message: 'Invalid parameter' } }.to_json,
                                       headers: { 'Content-Type' => 'application/json' })
    expect(service.perform).to eq(:rejected)
    expect(contact.reload.additional_attributes.dig('meta_capi', 'purchase:1', 'error')).to eq('Invalid parameter')
  end

  it 'raises a retryable error on 5xx' do
    stub_request(:post, url).to_return(status: 503, body: 'busy')
    expect { service.perform }.to raise_error(described_class::RetryableError)
  end

  it 'sends nothing while disabled' do
    settings['META_CAPI_ENABLED'] = nil
    expect(service.perform).to eq(:disabled)
  end
end
