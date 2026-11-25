# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/business_assistant_helpers')

RSpec.describe BusinessAssistant::Token do
  include BusinessAssistantHelpers

  let!(:settings) { configure_assistant! }
  let(:conversation) { assistant_conversation }
  let(:entry) { settings.phones.first }

  it 'emite e valida um token com telefone, escopo e conversa' do
    issued = described_class.issue(settings: settings, phone_entry: entry, conversation: conversation)
    context = described_class.verify!(issued[:token], settings: BusinessAssistant::Settings.load)
    expect(context.to_h).to include(phone: '+5562999990000', scope: 'owner', conversation_id: conversation.id,
                                    jti: issued[:jti])
  end

  it 'expira em 10 minutos' do
    issued = described_class.issue(settings: settings, phone_entry: entry, conversation: conversation)
    travel 11.minutes do
      expect { described_class.verify!(issued[:token], settings: settings) }.to raise_error(described_class::Invalid)
    end
  end

  it 'não vale em outra instalação' do
    issued = described_class.issue(settings: settings, phone_entry: entry, conversation: conversation)
    other = BusinessAssistant::Settings.load
    other.installation_id = SecureRandom.uuid
    expect { described_class.verify!(issued[:token], settings: other) }.to raise_error(described_class::Invalid)
  end

  it 'deixa de valer quando o telefone é removido ou o assistente é desligado' do
    issued = described_class.issue(settings: settings, phone_entry: entry, conversation: conversation)
    configure_assistant!(phones: [{ phone: '+5511988887777', name: 'Outro' }])
    expect { described_class.verify!(issued[:token]) }.to raise_error(described_class::Invalid, /telefone/)

    configure_assistant!(enabled: false)
    expect { described_class.verify!(issued[:token]) }.to raise_error(described_class::Invalid)
  end

  it 'recusa token adulterado ou ausente' do
    expect { described_class.verify!('abc.def.ghi', settings: settings) }.to raise_error(described_class::Invalid)
    expect { described_class.verify!(nil, settings: settings) }.to raise_error(described_class::Invalid)
  end
end
