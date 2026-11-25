# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/business_assistant_helpers')

RSpec.describe 'Assistant::V1::Replies', type: :request do
  include BusinessAssistantHelpers

  let!(:settings) { configure_assistant! }
  let(:conversation) { assistant_conversation }
  let(:issued) do
    BusinessAssistant::Token.issue(settings: settings, phone_entry: settings.phones.first, conversation: conversation)
  end
  let(:headers) { { 'Authorization' => "Bearer #{issued[:token]}" } }

  before { clear_assistant_redis! }

  it 'envia a resposta na conversa do token e fecha a pendência' do
    BusinessAssistant::PendingReply.open!(issued[:jti])
    post '/assistant/v1/replies', params: { content: 'Hoje: 3 vendas, R$ 1.240,00' }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    message = conversation.messages.outgoing.last
    expect(message.content).to eq('Hoje: 3 vendas, R$ 1.240,00')
    expect(message.inbox_id).to eq(assistant_inbox.id)
    expect(BusinessAssistant::PendingReply.close!(issued[:jti])).to be(false)
  end

  it 'recusa sem token, com token inválido e com JWT de usuário' do
    post '/assistant/v1/replies', params: { content: 'oi' }, as: :json
    expect(response).to have_http_status(:unauthorized)

    post '/assistant/v1/replies', params: { content: 'oi' }, headers: { 'Authorization' => 'Bearer xyz' }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(conversation.messages.outgoing).to be_empty
  end

  it 'recusa conversa que não é do telefone do token' do
    other = assistant_conversation('+5511988887777')
    configure_assistant!(phones: [{ phone: BusinessAssistantHelpers::OWNER_PHONE, name: 'Carla' },
                                  { phone: '+5511988887777', name: 'Outro' }])
    forged = BusinessAssistant::Token.issue(settings: BusinessAssistant::Settings.load,
                                            phone_entry: BusinessAssistant::Settings.load.phones.first,
                                            conversation: other)
    post '/assistant/v1/replies', params: { content: 'oi' }, headers: { 'Authorization' => "Bearer #{forged[:token]}" },
                                  as: :json
    expect(response).to have_http_status(:forbidden)
    expect(other.messages.outgoing).to be_empty
  end

  it 'valida o conteúdo' do
    post '/assistant/v1/replies', params: { content: '   ' }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
