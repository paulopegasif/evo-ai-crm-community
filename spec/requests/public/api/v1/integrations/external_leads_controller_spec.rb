# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public::Api::V1::Integrations::ExternalLeads', type: :request do
  let!(:user) { User.create!(email: 'admin@lumombeauty.com.br', name: 'Admin') }
  let!(:access_token) { AccessToken.create!(owner: user, name: 'n8n integration', scopes: 'all', token: SecureRandom.hex(32)) }
  let!(:pipeline) { Pipeline.create!(name: 'Jornada do Paciente', pipeline_type: 'sales', created_by: user) }
  let!(:stage) { PipelineStage.create!(pipeline: pipeline, name: '1. Novos Leads', position: 1, stage_type: 'active') }

  let(:headers) do
    {
      'X-API-Key' => access_token.token,
      'Content-Type' => 'application/json'
    }
  end

  let(:valid_payload) do
    {
      source: 'bitrix24',
      external_id: 'deal-999',
      contact: {
        name: 'Ana Carolina',
        phone_number: '+5561991234567',
        email: 'ana@example.com',
        created_at: '2026-08-10T14:20:00-03:00'
      },
      deal: {
        pipeline_id: pipeline.id,
        stage_id: stage.id,
        value: 350.00
      }
    }
  end

  describe 'POST /public/api/v1/integrations/external_leads' do
    it 'returns 401 when API key is missing' do
      post '/public/api/v1/integrations/external_leads',
           params: valid_payload.to_json,
           headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
      json = response.parsed_body
      expect(json['success']).to be(false)
      expect(json['error']).to eq('API key is missing')
    end

    it 'returns 401 when API key is invalid' do
      post '/public/api/v1/integrations/external_leads',
           params: valid_payload.to_json,
           headers: { 'X-API-Key' => 'invalid-token', 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
      json = response.parsed_body
      expect(json['success']).to be(false)
      expect(json['error']).to eq('Invalid API key')
    end

    it 'returns 422 without side effects when payload is invalid' do
      invalid_payload = valid_payload.deep_dup
      invalid_payload.delete(:source)

      expect do
        post '/public/api/v1/integrations/external_leads',
             params: invalid_payload.to_json,
             headers: headers
      end.not_to change(Contact, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json['success']).to be(false)
      expect(json['errors']).to include('source is required')
    end

    it 'returns 201 on initial sync with created actions and IDs' do
      post '/public/api/v1/integrations/external_leads',
           params: valid_payload.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['contact']['action']).to eq('created')
      expect(json['contact']['id']).to be_present
      expect(json['pipeline_item']['action']).to eq('created')
      expect(json['pipeline_item']['id']).to be_present
    end

    it 'returns 200 on repeat sync with unchanged actions' do
      post '/public/api/v1/integrations/external_leads',
           params: valid_payload.to_json,
           headers: headers
      expect(response).to have_http_status(:created)

      post '/public/api/v1/integrations/external_leads',
           params: valid_payload.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['success']).to be(true)
      expect(json['contact']['action']).to eq('unchanged')
      expect(json['pipeline_item']['action']).to eq('unchanged')
    end
  end
end
