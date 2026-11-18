# frozen_string_literal: true

require 'rails_helper'

# Agent edits / deletes an outgoing message in the CRM -> mirror it on WhatsApp
# through Evolution Go (/message/edit and /message/delete).
RSpec.describe Whatsapp::Providers::EvolutionGoService do
  let(:channel) do
    instance_double(Channel::Whatsapp,
                    provider_config: { 'api_url' => 'http://evo-go:8080', 'instance_token' => 'itok' })
  end
  let(:service) { described_class.new(whatsapp_channel: channel) }
  let(:message) { double('Message', source_id: 'WAID1') }

  before do
    allow(Whatsapp::SendOnWhatsappService).to receive(:target_jid_for).with(message).and_return('75595736191090@lid')
  end

  describe '#delete_message' do
    it 'revokes on the chat the message was sent to and returns true' do
      expect(HTTParty).to receive(:post) do |url, opts|
        expect(url).to eq('http://evo-go:8080/message/delete')
        expect(JSON.parse(opts[:body])).to eq('chat' => '75595736191090@lid', 'messageId' => 'WAID1')
        expect(opts[:headers]['apikey']).to eq('itok')
        double(success?: true, code: 200)
      end
      expect(service.delete_message(message)).to be(true)
    end

    it 'returns false (CRM-only delete) when the provider refuses' do
      allow(HTTParty).to receive(:post).and_return(double(success?: false, code: 500, body: 'err'))
      expect(service.delete_message(message)).to be(false)
    end

    it 'does not call the provider for a message that never reached WhatsApp' do
      unsent = double('Message', source_id: nil)
      expect(HTTParty).not_to receive(:post)
      expect(service.delete_message(unsent)).to be(false)
    end
  end

  describe '#edit_message' do
    it 'sends the new text to /message/edit' do
      expect(HTTParty).to receive(:post) do |url, opts|
        expect(url).to eq('http://evo-go:8080/message/edit')
        expect(JSON.parse(opts[:body])).to eq('chat' => '75595736191090@lid', 'messageId' => 'WAID1', 'message' => 'novo texto')
        double(success?: true, code: 200)
      end
      expect(service.edit_message(message, 'novo texto')).to be(true)
    end

    it 'raises with the provider error so the CRM keeps the original' do
      allow(HTTParty).to receive(:post).and_return(double(success?: false, code: 500, body: '{"error":"too old"}'))
      expect { service.edit_message(message, 'x') }.to raise_error(/HTTP 500/)
    end
  end
end

RSpec.describe Whatsapp::SendOnWhatsappService, '.target_jid_for' do
  let(:channel) { instance_double(Channel::Whatsapp, provider: 'evolution_go') }
  let(:contact) { double('Contact', id: 1, identifier: identifier, phone_number: '+5511999990000') }
  let(:contact_inbox) { double('ContactInbox', source_id: '5511999990000') }
  let(:conversation) do
    double('Conversation', contact: contact, contact_inbox: contact_inbox, additional_attributes: {},
                           inbox: double('Inbox', channel: channel))
  end
  let(:message) { double('Message', conversation: conversation) }

  context 'with a LID identifier' do
    let(:identifier) { '75595736191090@lid' }

    it 'returns the LID JID as-is' do
      expect(described_class.target_jid_for(message)).to eq('75595736191090@lid')
    end
  end

  context 'with only a phone number' do
    let(:identifier) { nil }

    it 'builds the s.whatsapp.net JID' do
      expect(described_class.target_jid_for(message)).to eq('5511999990000@s.whatsapp.net')
    end
  end
end
