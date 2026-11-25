# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe 'Api::V1::SalesGoals', type: :request do
  include SalesFixtures
  include SalesAuthHelpers

  around { |example| with_auth_env { example.run } }

  let!(:admin) { create_user('Admin') }
  let!(:ana) { create_user('Ana') }
  let(:admin_headers) { auth_headers_for(admin, role: 'administrator') }

  it 'agente recebe 403 ao criar meta' do
    put '/api/v1/sales_goals', params: { month: '2026-11', amount: 1000 }, headers: auth_headers_for(ana), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it 'admin cria e atualiza meta geral e por vendedor e lista o mês' do
    put '/api/v1/sales_goals', params: { month: '2026-11', amount: 20_000 }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:ok)
    put '/api/v1/sales_goals', params: { month: '2026-11', amount: 25_000 }, headers: admin_headers, as: :json
    put '/api/v1/sales_goals', params: { month: '2026-11', user_id: ana.id, amount: 5000 }, headers: admin_headers, as: :json
    expect(SalesGoal.count).to eq(2)

    get '/api/v1/sales_goals', params: { month: '2026-11' }, headers: admin_headers
    expect(json_data['general']['goal']).to eq(25_000.0)
    ana_row = json_data['sellers'].find { |row| row['user']['id'] == ana.id }
    expect(ana_row['goal']).to eq(5000.0)
  end

  it 'admin remove meta' do
    goal = SalesGoal.create!(month: Date.new(2026, 11, 1), amount: 10)
    delete "/api/v1/sales_goals/#{goal.id}", headers: admin_headers
    expect(response).to have_http_status(:ok)
    expect(SalesGoal.count).to eq(0)
  end

  it 'mês inválido retorna 422' do
    put '/api/v1/sales_goals', params: { month: 'nov', amount: 10 }, headers: admin_headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
