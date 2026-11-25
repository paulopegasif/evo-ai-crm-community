# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'
require Rails.root.join('spec/support/business_assistant_helpers')

RSpec.describe BusinessAssistant::DispatchJob do
  include BusinessAssistantHelpers
  include ActiveJob::TestHelper

  let!(:settings) { configure_assistant! }
  let(:conversation) { assistant_conversation }

  before { clear_assistant_redis! }
  after { clear_assistant_redis! }

  def outgoing_contents
    conversation.reload.messages.outgoing.pluck(:content)
  end

  describe 'listener' do
    def fire(message)
      BusinessAssistantListener.instance.message_created(Events::Base.new('message.created', Time.current, message: message))
    end

    it 'enfileira job para telefone liberado' do
      message = incoming_message(conversation)
      expect { fire(message) }.to have_enqueued_job(described_class).with(message.id)
    end

    it 'ignora telefone desconhecido, outra caixa, mensagens de saída e assistente desligado' do
      stranger = incoming_message(assistant_conversation('+5511988887777'))
      other_inbox = Inbox.create!(name: 'Atendimento', channel: Channel::Api.create!)
      elsewhere = incoming_message(assistant_conversation(BusinessAssistantHelpers::OWNER_PHONE, inbox: other_inbox))
      outgoing = conversation.messages.create!(content: 'oi', message_type: :outgoing, inbox_id: conversation.inbox_id)

      expect { [stranger, elsewhere, outgoing].each { |m| fire(m) } }.not_to have_enqueued_job(described_class)

      configure_assistant!(enabled: false)
      expect { fire(incoming_message(conversation)) }.not_to have_enqueued_job(described_class)
    end
  end

  it 'encaminha com assinatura, token e escopo e agenda o vigia' do
    received = nil
    stub_request(:post, BusinessAssistantHelpers::WEBHOOK_URL).with do |req|
      received = req
      true
    end.to_return(status: 200)

    message = incoming_message(conversation)
    expect { described_class.perform_now(message.id) }
      .to have_enqueued_job(BusinessAssistant::ReplyWatchdogJob).with(conversation.id, kind_of(String))

    body = JSON.parse(received.body)
    expect(body).to include('event' => 'message', 'installation_id' => settings.installation_id,
                            'conversation_id' => conversation.id, 'message_id' => message.id,
                            'phone' => '+5562999990000', 'name' => 'Carla', 'scope' => 'owner',
                            'text' => 'quanto vendi hoje?')
    expect(received.headers['X-Assistant-Signature']).to eq(
      BusinessAssistant::WebhookClient.signature(BusinessAssistantHelpers::SECRET,
                                                 received.headers['X-Assistant-Timestamp'], received.body)
    )
    expect(BusinessAssistant::Token.verify!(body['token']).conversation_id).to eq(conversation.id)
  end

  it 'conta o uso, marca a conversa como interna e não responde sozinho' do
    stub_request(:post, BusinessAssistantHelpers::WEBHOOK_URL).to_return(status: 200)
    described_class.perform_now(incoming_message(conversation).id)
    expect(BusinessAssistant::Usage.current_count).to eq(1)
    expect(conversation.reload.label_list).to include('assistente')
    expect(conversation.contact.reload.custom_attributes['internal_recipient']).to be(true)
    expect(outgoing_contents).to be_empty
  end

  it 'avisa indisponibilidade na hora quando o n8n recusa' do
    stub_request(:post, BusinessAssistantHelpers::WEBHOOK_URL).to_return(status: 502)
    described_class.perform_now(incoming_message(conversation).id)
    expect(outgoing_contents).to eq([BusinessAssistant::Notifier::MESSAGES[:unavailable]])
    expect(BusinessAssistant::Usage.current_count).to eq(0)
  end

  it 'pede texto quando a mensagem não tem conteúdo' do
    described_class.perform_now(incoming_message(conversation, '').id)
    expect(outgoing_contents).to eq([BusinessAssistant::Notifier::MESSAGES[:text_only]])
  end

  it 'para no limite mensal e avisa uma vez por dia' do
    configure_assistant!(monthly_limit: 1)
    BusinessAssistant::Usage.increment!
    2.times { described_class.perform_now(incoming_message(conversation).id) }
    expect(outgoing_contents).to eq([BusinessAssistant::Notifier::MESSAGES[:limit_reached]])
    expect(a_request(:post, BusinessAssistantHelpers::WEBHOOK_URL)).not_to have_been_made
  end

  describe BusinessAssistant::ReplyWatchdogJob do
    it 'avisa uma única vez se ninguém respondeu' do
      BusinessAssistant::PendingReply.open!('jti-1')
      2.times { described_class.perform_now(conversation.id, 'jti-1') }
      expect(outgoing_contents).to eq([BusinessAssistant::Notifier::MESSAGES[:unavailable]])
    end

    it 'não avisa se a resposta já chegou' do
      BusinessAssistant::PendingReply.open!('jti-2')
      BusinessAssistant::PendingReply.close!('jti-2')
      described_class.perform_now(conversation.id, 'jti-2')
      expect(outgoing_contents).to be_empty
    end
  end

  it 'a conversa do assistente não entra no Painel do Dia' do
    stub_request(:post, BusinessAssistantHelpers::WEBHOOK_URL).to_return(status: 200)
    described_class.perform_now(incoming_message(conversation).id)
    panel = DailyPanel::BuildService.new(user: nil, admin: true, today: Sales::TimeZone.today).call
    expect(panel[:todo][:awaiting_reply]).to eq(0)
  end
end
