# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe 'Api::V1::Sales', type: :request do
  include SalesFixtures
  include SalesAuthHelpers

  around { |example| with_auth_env { example.run } }

  let!(:admin) { create_user('Admin') }
  let!(:ana) { create_user('Ana') }
  let!(:bia) { create_user('Bia') }
  let(:contact) { create_contact }
  let(:conversation) { create_conversation(contact: contact) }

  describe 'POST /api/v1/sales' do
    it 'registra venda com valor e conversa' do
      post '/api/v1/sales', params: { sale: { amount: '350', conversation_id: conversation.id } },
                            headers: auth_headers_for(ana), as: :json
      expect(response).to have_http_status(:created)
      expect(json_data['amount']).to eq(350.0)
      expect(json_data['seller']['id']).to eq(ana.id)
      expect(json_data['contact']['id']).to eq(contact.id)
    end

    it 'recusa valor zero com 422' do
      post '/api/v1/sales', params: { sale: { amount: 0, conversation_id: conversation.id } },
                            headers: auth_headers_for(ana), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'ignora seller_id enviado por agente' do
      post '/api/v1/sales', params: { sale: { amount: 10, seller_id: bia.id } }, headers: auth_headers_for(ana), as: :json
      expect(json_data['seller']['id']).to eq(ana.id)
    end

    it 'admin pode registrar em nome de outro vendedor' do
      post '/api/v1/sales', params: { sale: { amount: 10, seller_id: bia.id } },
                            headers: auth_headers_for(admin, role: 'administrator'), as: :json
      expect(json_data['seller']['id']).to eq(bia.id)
    end
  end

  describe 'GET /api/v1/sales/sellers' do
    it 'lista usuários do CRM para admin e recusa agente' do
      get '/api/v1/sales/sellers', headers: auth_headers_for(admin, role: 'administrator')
      expect(json_data.map { |u| u['id'] }).to include(ana.id, bia.id)

      get '/api/v1/sales/sellers', headers: auth_headers_for(ana)
      expect(response).to have_http_status(:forbidden)
    end

    it 'recusa seller_id que não é usuário do CRM' do
      post '/api/v1/sales', params: { sale: { amount: 10, seller_id: SecureRandom.uuid } },
                            headers: auth_headers_for(admin, role: 'administrator'), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET /api/v1/sales' do
    before do
      create_sale(amount: 10, seller: ana, created_by: ana)
      create_sale(amount: 20, seller: bia, created_by: bia)
    end

    it 'agente vê só as próprias vendas' do
      get '/api/v1/sales', headers: auth_headers_for(ana)
      expect(json_data.map { |s| s['seller']['id'] }).to eq([ana.id])
    end

    it 'admin vê todas' do
      get '/api/v1/sales', headers: auth_headers_for(admin, role: 'administrator')
      expect(json_data.size).to eq(2)
    end
  end

  describe 'PATCH e cancel' do
    let!(:bia_sale) { create_sale(amount: 350, seller: bia, created_by: bia) }

    it 'agente não cancela venda de outro agente' do
      post "/api/v1/sales/#{bia_sale.id}/cancel", headers: auth_headers_for(ana)
      expect(response).to have_http_status(:forbidden)
      expect(bia_sale.reload.status).to eq('active')
    end

    it 'admin corrige o valor' do
      patch "/api/v1/sales/#{bia_sale.id}", params: { sale: { amount: 530 } },
                                            headers: auth_headers_for(admin, role: 'administrator'), as: :json
      expect(response).to have_http_status(:ok)
      expect(bia_sale.reload.amount).to eq(530)
    end

    it 'quem registrou pode cancelar' do
      post "/api/v1/sales/#{bia_sale.id}/cancel", headers: auth_headers_for(bia)
      expect(response).to have_http_status(:ok)
      expect(json_data['status']).to eq('cancelled')
    end
  end
end
