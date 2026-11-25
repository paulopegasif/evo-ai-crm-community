# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'
require Rails.root.join('spec/support/sales_fixtures')
require Rails.root.join('spec/support/business_assistant_helpers')

RSpec.describe 'Api::V1::BusinessAssistantSettings', type: :request do
  include SalesFixtures
  include SalesAuthHelpers
  include BusinessAssistantHelpers

  around { |example| with_auth_env { example.run } }

  let!(:root) { create_user('Root') }
  let(:headers) { auth_headers_for(root, role: 'super_admin') }
  let(:valid_params) do
    { business_assistant_settings: {
      enabled: true, inbox_id: assistant_inbox.id, webhook_url: BusinessAssistantHelpers::WEBHOOK_URL,
      regenerate_secret: true, monthly_limit: 300,
      phones: [{ phone: '+5561999990000', name: 'Carla', scope: 'owner' }]
    } }
  end

  before do
    stub_whatsapp_inboxes
    clear_assistant_redis!
  end

  %w[account_owner administrator agent].each do |role|
    it "#{role} recebe 403 ao ler ou salvar" do
      user = create_user(role)
      get '/api/v1/business_assistant_settings', headers: auth_headers_for(user, role: role)
      expect(response).to have_http_status(:forbidden)

      put '/api/v1/business_assistant_settings', params: valid_params, headers: auth_headers_for(user, role: role), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(BusinessAssistant::Settings.load.enabled).to be(false)
    end
  end

  it 'super admin salva e recebe o segredo gerado uma única vez' do
    put '/api/v1/business_assistant_settings', params: valid_params, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(json_data).to include('enabled' => true, 'secret_set' => true)
    expect(json_data['generated_secret']).to match(/\A\h{64}\z/)
    expect(json_data['installation_id']).to be_present
  end

  it 'nunca devolve o segredo na leitura' do
    put '/api/v1/business_assistant_settings', params: valid_params, headers: headers, as: :json
    get '/api/v1/business_assistant_settings', headers: headers
    expect(json_data).not_to have_key('generated_secret')
    expect(json_data).not_to have_key('signing_secret_ciphertext')
    expect(json_data['phones'].first).to include('name' => 'Carla')
    expect(json_data['available_inboxes'].first['id']).to eq(assistant_inbox.id)
  end

  it 'retorna 422 com detalhes por campo' do
    put '/api/v1/business_assistant_settings',
        params: { business_assistant_settings: { enabled: true, phones: [{ phone: '12', name: 'X' }] } },
        headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    fields = response.parsed_body['error']['details'].pluck('field')
    expect(fields).to include('inbox_id', 'phones')
  end

  describe 'teste de conexão' do
    before { configure_assistant! }

    it 'mostra sucesso e latência, com evento ping assinado' do
      stub = stub_request(:post, BusinessAssistantHelpers::WEBHOOK_URL).with do |req|
        body = JSON.parse(req.body)
        expected = BusinessAssistant::WebhookClient.signature(
          BusinessAssistantHelpers::SECRET, req.headers['X-Assistant-Timestamp'], req.body
        )
        body['event'] == 'ping' && req.headers['X-Assistant-Signature'] == expected
      end.to_return(status: 200, body: '{}')

      post '/api/v1/business_assistant_settings/test', headers: headers
      expect(stub).to have_been_requested
      expect(json_data).to include('ok' => true, 'status' => 200)
      expect(json_data['latency_ms']).to be_a(Integer)
    end

    it 'mostra a falha com o código HTTP' do
      stub_request(:post, BusinessAssistantHelpers::WEBHOOK_URL).to_return(status: 500)
      post '/api/v1/business_assistant_settings/test', headers: headers
      expect(json_data).to include('ok' => false, 'status' => 500, 'error' => 'HTTP 500')
    end

    it 'mostra timeout' do
      stub_request(:post, BusinessAssistantHelpers::WEBHOOK_URL).to_timeout
      post '/api/v1/business_assistant_settings/test', headers: headers
      expect(json_data['ok']).to be(false)
      expect(json_data['error']).to be_present
      expect(BusinessAssistant::Settings.load.enabled).to be(true)
    end
  end
end
