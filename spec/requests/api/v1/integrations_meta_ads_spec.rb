# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Integrations Meta Ads', type: :request do
  let(:user) { User.create!(name: 'Perm Probe', email: "probe-#{SecureRandom.hex(4)}@example.com") }
  let(:graph) { "https://graph.facebook.com/#{MetaAds::GraphClient::DEFAULT_VERSION}" }
  let(:token) { 'EAABwzLixnjYBOtestTOKENvalue9xyz9' }
  let(:path) { '/api/v1/integrations/meta_ads' }

  before do
    probe = user
    allow_any_instance_of(Api::BaseController).to receive(:authenticate_request!) do
      Current.user = probe
      Current.evo_permission_cache ||= {}
    end
    grant_permissions('integrations.read', 'integrations.update', 'integrations.execute', 'integrations.delete')
    allow(MetaAds::SyncLock).to receive(:locked?).and_return(false)
    allow(MetaAds::SyncJob).to receive(:perform_later)
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('META_GRAPH_API_VERSION', nil).and_return(nil)
    allow(GlobalConfigService).to receive(:load).with('META_APP_SECRET', nil).and_return(nil)
  end

  after { Current.reset }

  def grant_permissions(*granted)
    allow_any_instance_of(EvoAuthService).to receive(:check_user_permission) do |_service, _user_id, permission|
      granted.include?(permission)
    end
  end

  def stub_me(status: 200, body: { id: '1', name: 'System User' })
    stub_request(:get, "#{graph}/me").with(query: hash_including({})).to_return(
      status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def stub_account(id = 'act_1234567890', status: 200, body: nil)
    body ||= { id: id, name: 'Lumom Beauty', currency: 'BRL', timezone_name: 'America/Sao_Paulo', account_status: 1 }
    stub_request(:get, "#{graph}/#{id}").with(query: hash_including({})).to_return(
      status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' }
    )
  end

  def graph_error(code, message = 'Error')
    { error: { message: message, type: 'OAuthException', code: code } }
  end

  def data
    JSON.parse(response.body)['data']
  end

  def connect!
    stub_me
    stub_account
    put path, params: { ad_account_id: '1234567890', access_token: token }, as: :json
  end

  describe 'GET /api/v1/integrations/meta_ads' do
    it 'reports not configured when there is no integration' do
      get path

      expect(response).to have_http_status(:ok)
      expect(data).to include('configured' => false, 'connection_status' => 'not_configured')
    end

    it 'denies a user without integrations.read' do
      grant_permissions('integrations.update')
      get path
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PUT /api/v1/integrations/meta_ads' do
    it 'validates and stores the connection with a normalized account id and encrypted token' do
      connect!

      expect(response).to have_http_status(:ok)
      expect(data).to include(
        'configured' => true, 'connection_status' => 'connected', 'ad_account_id' => 'act_1234567890',
        'account_name' => 'Lumom Beauty', 'currency' => 'BRL', 'timezone_name' => 'America/Sao_Paulo',
        'token_hint' => 'EAAB…xyz9'
      )
      expect(response.body).not_to include(token)

      hook = Integrations::Hook.find_by(app_id: 'meta_ads')
      expect(hook.settings['access_token_encrypted']).to be_present
      expect(hook.settings.to_json).not_to include(token)
      expect(MetaAds::Integration.current.access_token).to eq(token)
      expect(MetaAds::SyncJob).to have_received(:perform_later)
    end

    it 'persists nothing when Meta rejects the token' do
      stub_me(status: 400, body: graph_error(190, 'Error validating access token: Session has expired'))

      put path, params: { ad_account_id: 'act_1234567890', access_token: 'bad' }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig('error', 'message')).to include('Token de acesso inválido', 'Session has expired')
      expect(Integrations::Hook.where(app_id: 'meta_ads')).to be_empty
    end

    it 'explains when the token has no access to the ad account' do
      stub_me
      stub_account(status: 400, body: graph_error(200, 'Permissions error'))

      put path, params: { ad_account_id: 'act_1234567890', access_token: token }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body).dig('error', 'message')).to include('ads_read')
      expect(Integrations::Hook.where(app_id: 'meta_ads')).to be_empty
    end

    it 'rejects a malformed account id without calling Meta' do
      put path, params: { ad_account_id: 'act_abc', access_token: token }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(WebMock).not_to have_requested(:get, /graph\.facebook\.com/)
    end

    it 'keeps the stored token when the field is left blank' do
      connect!
      stub_account('act_999999999')

      put path, params: { ad_account_id: 'act_999999999', access_token: '' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(data['ad_account_id']).to eq('act_999999999')
      expect(MetaAds::Integration.current.access_token).to eq(token)
    end
  end

  describe 'token exposure' do
    it 'shows the catalog card as disconnected once the token is invalid' do
      connect!
      MetaAds::Integration.current.write!('connection_status' => 'token_invalid')

      get '/api/v1/integrations/apps'

      card = JSON.parse(response.body)['data'].find { |app| app['id'] == 'meta_ads' }
      expect(card['enabled']).to be(false)
    end

    it 'never returns the token from the generic integrations catalog' do
      connect!

      get '/api/v1/integrations/apps'

      expect(response.body).not_to include(token)
      expect(response.body).not_to include('access_token_encrypted')
    end

    it 'blocks creating a meta_ads hook through the generic hooks endpoint' do
      grant_permissions('integrations.create')

      post '/api/v1/integrations/hooks',
           params: { hook: { app_id: 'meta_ads', settings: { ad_account_id: 'act_1' } } }, as: :json

      expect(response.status).to be >= 400
      expect(Integrations::Hook.where(app_id: 'meta_ads')).to be_empty
    end
  end

  describe 'POST /api/v1/integrations/meta_ads/test' do
    it 'marks the integration as token_invalid on OAuthException 190' do
      connect!
      stub_me(status: 400, body: graph_error(190, 'Token revoked'))

      post "#{path}/test"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(MetaAds::Integration.current.connection_status).to eq('token_invalid')
    end

    it 'returns 404 when not configured' do
      post "#{path}/test"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/integrations/meta_ads/sync' do
    it 'enqueues the sync job' do
      connect!

      post "#{path}/sync"

      expect(response).to have_http_status(:accepted)
      expect(MetaAds::SyncJob).to have_received(:perform_later).twice
    end

    it 'answers 409 while a sync is running' do
      connect!
      allow(MetaAds::SyncLock).to receive(:locked?).and_return(true)

      post "#{path}/sync"

      expect(response).to have_http_status(:conflict)
    end
  end

  describe 'DELETE /api/v1/integrations/meta_ads' do
    it 'removes the token but keeps imported campaigns' do
      connect!
      MetaAds::Campaign.create!(meta_id: '6001', ad_account_id: 'act_1234567890', name: 'Botox Outubro')

      delete path

      expect(response).to have_http_status(:ok)
      expect(Integrations::Hook.where(app_id: 'meta_ads')).to be_empty
      expect(MetaAds::Campaign.count).to eq(1)
    end
  end
end
