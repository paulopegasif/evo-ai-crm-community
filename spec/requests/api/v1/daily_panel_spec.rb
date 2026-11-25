# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe 'Api::V1::DailyPanel', type: :request do
  include SalesFixtures
  include SalesAuthHelpers

  around { |example| with_auth_env { example.run } }

  let!(:admin) { create_user('Admin') }
  let!(:ana) { create_user('Ana Souza') }

  it 'retorna o painel do usuário' do
    get '/api/v1/daily_panel', headers: auth_headers_for(ana)
    expect(response).to have_http_status(:ok)
    expect(json_data['user']).to eq('first_name' => 'Ana', 'is_admin' => false)
    expect(json_data.keys).to include('quote', 'sales', 'month', 'todo', 'no_sales_hint')
  end

  it 'salva e limpa a preferência de frase do usuário' do
    patch '/api/v1/daily_panel/preferences', params: { daily_quote_category: 'biblia' }, headers: auth_headers_for(ana), as: :json
    expect(json_data['daily_quote_category']).to eq('biblia')
    expect(ana.reload.ui_settings['daily_quote_category']).to eq('biblia')

    patch '/api/v1/daily_panel/preferences', params: { daily_quote_category: nil }, headers: auth_headers_for(ana), as: :json
    expect(json_data['daily_quote_category']).to be_nil
  end

  it 'recusa categoria inválida' do
    patch '/api/v1/daily_panel/preferences', params: { daily_quote_category: 'x' }, headers: auth_headers_for(ana), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'só admin altera o padrão da instalação' do
    patch '/api/v1/daily_panel/settings', params: { default_quote_category: 'off' }, headers: auth_headers_for(ana), as: :json
    expect(response).to have_http_status(:forbidden)

    patch '/api/v1/daily_panel/settings', params: { default_quote_category: 'off' },
                                          headers: auth_headers_for(admin, role: 'administrator'), as: :json
    expect(response).to have_http_status(:ok)
    expect(json_data['default_quote_category']).to eq('off')
  end
end
