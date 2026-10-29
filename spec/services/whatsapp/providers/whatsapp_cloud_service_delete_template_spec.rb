# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Whatsapp::Providers::WhatsappCloudService do
  let(:whatsapp_channel) do
    instance_double(Channel::Whatsapp, provider_config: { 'api_key' => 'api-token', 'waba_id' => '999' })
  end
  let(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }
  let(:templates_url) { "#{MetaBaseUrl.for(:whatsapp)}/999/message_templates" }

  describe '#delete_template' do
    it 'deletes only that language on Meta, by name and hsm_id' do
      template = instance_double(MessageTemplate, name: 'lembrete', metadata: { 'external_id' => '123' })
      request = stub_request(:delete, templates_url)
                .with(query: { name: 'lembrete', hsm_id: '123' }, headers: { 'Authorization' => 'Bearer api-token' })
                .to_return(status: 200, body: '{"success":true}', headers: { 'Content-Type' => 'application/json' })

      expect(service.delete_template(template)).to be(true)
      expect(request).to have_been_requested
    end

    it 'raises with the Meta error so the local record is kept' do
      template = instance_double(MessageTemplate, name: 'lembrete', metadata: { 'external_id' => '123' })
      stub_request(:delete, templates_url).with(query: hash_including({}))
                                          .to_return(status: 400, body: { error: { message: 'Invalid parameter' } }.to_json,
                                                     headers: { 'Content-Type' => 'application/json' })

      expect { service.delete_template(template) }.to raise_error(StandardError, /Invalid parameter/)
    end

    it 'skips Meta for templates that were never synced' do
      template = instance_double(MessageTemplate, name: 'rascunho', metadata: {})

      expect(service.delete_template(template)).to be(true)
      expect(a_request(:delete, /message_templates/)).not_to have_been_made
    end
  end
end
