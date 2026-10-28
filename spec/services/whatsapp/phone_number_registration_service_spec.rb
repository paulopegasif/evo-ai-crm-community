# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe Whatsapp::PhoneNumberRegistrationService do
  describe '#perform' do
    let(:channel) do
      Channel::Whatsapp.new(
        provider: 'whatsapp_cloud',
        phone_number: '+5511900000001',
        provider_config: { 'phone_number_id' => '123', 'api_key' => 'token', 'waba_id' => '456' }
      )
    end
    let(:service) { described_class.new(channel: channel) }
    let(:phone_url) { 'https://graph.facebook.com/v23.0/123?fields=platform_type' }
    let(:register_url) { 'https://graph.facebook.com/v23.0/123/register' }

    before do
      allow(MetaBaseUrl).to receive(:enabled?).and_return(false)
      allow(channel).to receive(:update_columns)
    end

    it 'registers an unregistered number and stores the generated pin' do
      stub_request(:get, phone_url).to_return(
        status: 200, body: { platform_type: 'NOT_APPLICABLE' }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      register = stub_request(:post, register_url)
                 .with(body: hash_including('messaging_product' => 'whatsapp'))
                 .to_return(status: 200, body: '{"success":true}')

      service.perform

      expect(register).to have_been_requested
      expect(channel).to have_received(:update_columns)
        .with(provider_config: hash_including('two_step_pin' => match(/\A\d{6}\z/)))
    end

    it 'skips numbers already on Cloud API' do
      stub_request(:get, phone_url).to_return(
        status: 200, body: { platform_type: 'CLOUD_API' }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      register = stub_request(:post, register_url)

      service.perform

      expect(register).not_to have_been_requested
      expect(channel).not_to have_received(:update_columns)
    end

    it 'ignores channels from other providers' do
      channel.provider = 'evolution_go'

      service.perform

      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'does not store a pin when Meta rejects the registration' do
      stub_request(:get, phone_url).to_return(
        status: 200, body: { platform_type: 'NOT_APPLICABLE' }.to_json, headers: { 'Content-Type' => 'application/json' }
      )
      stub_request(:post, register_url).to_return(status: 400, body: '{"error":{}}')

      service.perform

      expect(channel).not_to have_received(:update_columns)
    end
  end
end
