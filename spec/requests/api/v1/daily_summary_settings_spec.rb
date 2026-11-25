# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe 'Api::V1::DailySummarySettings', type: :request do
  include SalesFixtures
  include SalesAuthHelpers

  around { |example| with_auth_env { example.run } }

  let!(:admin) { create_user('Admin') }
  let!(:ana) { create_user('Ana') }
  let(:inbox) { Inbox.create!(name: 'Atendimento', channel: Channel::Api.create!) }
  let(:admin_headers) { auth_headers_for(admin, role: 'administrator') }

  before { allow(DailySummary::Settings).to receive(:whatsapp_inboxes).and_return(Inbox.where(id: inbox.id)) }

  it 'agente não acessa' do
    get '/api/v1/daily_summary_settings', headers: auth_headers_for(ana)
    expect(response).to have_http_status(:forbidden)
  end

  it 'admin lê, salva e vê caixas disponíveis' do
    get '/api/v1/daily_summary_settings', headers: admin_headers
    expect(json_data).to include('enabled' => false, 'time' => '19:00')
    expect(json_data['available_inboxes'].first['id']).to eq(inbox.id)

    put '/api/v1/daily_summary_settings',
        params: { daily_summary_settings: { enabled: true, time: '18:30', inbox_id: inbox.id, phones: ['+5562999990000'] } },
        headers: admin_headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(json_data).to include('enabled' => true, 'time' => '18:30', 'phones' => ['+5562999990000'])
  end

  it 'retorna 422 com números inválidos' do
    put '/api/v1/daily_summary_settings',
        params: { daily_summary_settings: { enabled: true, inbox_id: inbox.id, phones: ['12'] } },
        headers: admin_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)['error']['details'].first['field']).to eq('phones')
  end

  it 'envio de teste exige configuração' do
    post '/api/v1/daily_summary_settings/test', headers: admin_headers
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
