# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe 'Integrations Meta Conversions', type: :request do
  let(:user) { User.create!(name: 'Perm Probe', email: "probe-#{SecureRandom.hex(4)}@example.com") }
  let(:graph) { "https://graph.facebook.com/#{MetaAds::GraphClient::DEFAULT_VERSION}" }
  let(:token) { 'EAABwzLixnjYBOcapiTOKENvalue9xyz9' }
  let(:path) { '/api/v1/integrations/meta_conversions' }
  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  before do
    probe = user
    allow_any_instance_of(Api::BaseController).to receive(:authenticate_request!) do
      Current.user = probe
      Current.evo_permission_cache ||= {}
    end
    grant_permissions('integrations.read', 'integrations.update', 'integrations.delete')
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

  def stub_permissions(granted = %w[whatsapp_business_management whatsapp_business_manage_events business_management])
    body = { data: granted.map { |p| { permission: p, status: 'granted' } } }
    stub_request(:get, "#{graph}/me/permissions").with(query: hash_including({}))
                                                 .to_return(status: 200, body: body.to_json, headers: json_headers)
  end

  def stub_waba(status: 200, body: { id: '102290129340398', name: 'Lumom WhatsApp' })
    stub_request(:get, "#{graph}/102290129340398").with(query: hash_including({}))
                                                  .to_return(status: status, body: body.to_json, headers: json_headers)
  end

  def stub_dataset(existing: nil)
    get_body = existing ? { data: [{ id: existing }] } : { data: [] }
    stub_request(:get, "#{graph}/102290129340398/dataset").with(query: hash_including({}))
                                                          .to_return(status: 200, body: get_body.to_json, headers: json_headers)
    stub_request(:post, "#{graph}/102290129340398/dataset").to_return(status: 200, body: { id: '999' }.to_json, headers: json_headers)
  end

  def data
    response.parsed_body['data']
  end

  def connect!(**extra)
    stub_permissions
    stub_waba
    stub_dataset
    put path, params: { waba_id: '102290129340398', access_token: token, enabled: true, test_event_code: 'TEST123' }.merge(extra), as: :json
  end

  it 'reports not configured when there is no integration' do
    get path
    expect(response).to have_http_status(:ok)
    expect(data).to include('configured' => false, 'enabled' => false, 'connection_status' => 'not_configured')
  end

  it 'validates the token, creates the dataset and stores the settings with an encrypted token' do
    connect!(event_names: { qualified: 'Schedule', lead: 'LeadSubmitted' })

    expect(response).to have_http_status(:ok)
    expect(data).to include('configured' => true, 'enabled' => true, 'waba_id' => '102290129340398', 'waba_name' => 'Lumom WhatsApp',
                            'dataset_id' => '999', 'token_source' => 'own', 'token_hint' => 'EAAB…xyz9')
    expect(data['event_names']).to eq('lead' => 'LeadSubmitted', 'qualified' => 'Schedule', 'purchase' => 'Purchase')
    expect(response.body).not_to include(token)
  end

  it 'stores the token encrypted and only the custom event names' do
    connect!(event_names: { qualified: 'Schedule', lead: 'LeadSubmitted' })

    settings = Integrations::Hook.find_by(app_id: 'meta_conversions').settings
    expect(settings['access_token_encrypted']).to be_present
    expect(settings['event_names']).to eq('qualified' => 'Schedule')
    expect(MetaConversions::Config.enabled?).to be(true)
    expect(MetaConversions::Config.access_token).to eq(token)
    expect(MetaConversions::Config.event_name(:qualified)).to eq('Schedule')
  end

  it 'reuses the existing dataset of the account' do
    stub_permissions
    stub_waba
    stub_dataset(existing: '555')
    put path, params: { waba_id: '102290129340398', access_token: token }, as: :json

    expect(data).to include('dataset_id' => '555', 'enabled' => false)
    expect(a_request(:post, "#{graph}/102290129340398/dataset")).not_to have_been_made
  end

  it 'keeps the stored token when saved again with a blank token' do
    connect!
    put path, params: { waba_id: '102290129340398', access_token: '', enabled: false }, as: :json

    expect(response).to have_http_status(:ok)
    expect(MetaConversions::Integration.current.access_token).to eq(token)
    expect(data['enabled']).to be(false)
  end

  it 'reuses the Meta Ads token when asked to' do
    Integrations::Hook.create!(app_id: 'meta_ads', settings: { 'ad_account_id' => 'act_1', 'token_hint' => 'ads…hint',
                                                               'access_token_encrypted' => MetaAds::Credentials.encrypt('ads-token') })
    stub_permissions
    stub_waba
    stub_dataset
    put path, params: { waba_id: '102290129340398', token_source: 'meta_ads' }, as: :json

    expect(response).to have_http_status(:ok)
    expect(data).to include('token_source' => 'meta_ads', 'token_hint' => 'ads…hint')
    expect(MetaConversions::Config.access_token).to eq('ads-token')
  end

  it 'explains missing permissions' do
    stub_permissions(%w[ads_read business_management])
    put path, params: { waba_id: '102290129340398', access_token: token }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('whatsapp_business_manage_events')
    expect(Integrations::Hook.exists?(app_id: 'meta_conversions')).to be(false)
  end

  it 'explains a token without access to the WhatsApp account' do
    stub_permissions
    stub_waba(status: 400, body: { error: { message: 'Unsupported get request', code: 100 } })
    put path, params: { waba_id: '102290129340398', access_token: token }, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('não acessa esta conta do WhatsApp Business')
  end

  it 'rejects a malformed account id' do
    put path, params: { waba_id: 'abc', access_token: token }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'denies saving without integrations.update' do
    grant_permissions('integrations.read')
    put path, params: { waba_id: '102290129340398', access_token: token }, as: :json
    expect(response).to have_http_status(:forbidden)
  end

  describe 'POST test_event' do
    it 'sends one synthetic event with the test code and returns Meta answer' do
      connect!
      stub = stub_request(:post, "https://graph.facebook.com/#{MetaConversions::Config.api_version}/999/events")
             .with do |req|
               body = JSON.parse(req.body)
               body['test_event_code'] == 'TEST123' && body['data'][0]['event_name'] == 'QualifiedLead'
             end
             .to_return(status: 200, body: { events_received: 1, fbtrace_id: 'abc' }.to_json, headers: json_headers)

      post "#{path}/test_event", params: { event: 'qualified' }, as: :json

      expect(stub).to have_been_requested
      expect(data).to include('success' => true, 'event_name' => 'QualifiedLead', 'events_received' => 1)
    end

    it 'returns the rejection message' do
      connect!
      stub_request(:post, %r{/999/events}).to_return(status: 400, body: { error: { message: 'Invalid event name' } }.to_json,
                                                     headers: json_headers)
      post "#{path}/test_event", params: { event: 'lead' }, as: :json

      expect(response).to have_http_status(:ok)
      expect(data).to include('success' => false, 'message' => 'Invalid event name')
    end

    it 'requires a test event code' do
      connect!(test_event_code: '')
      post "#{path}/test_event", params: { event: 'lead' }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'disconnects' do
    connect!
    delete path
    expect(response).to have_http_status(:ok)
    expect(Integrations::Hook.exists?(app_id: 'meta_conversions')).to be(false)
  end

  it 'reports delivery stats from the contacts log' do
    connect!
    Contact.create!(name: 'A', phone_number: '+5561985702132', additional_attributes: {
                      'meta_capi' => { 'lead' => { 'event' => 'LeadSubmitted', 'sent_at' => 1.hour.ago.iso8601 },
                                       'qualified' => { 'event' => 'QualifiedLead', 'failed_at' => 1.minute.ago.iso8601,
                                                        'error' => 'Invalid event name' } }
                    })
    get path

    expect(data['stats']).to include('sent' => 1, 'failed' => 1)
    expect(data['stats']['by_event']).to include('LeadSubmitted' => { 'sent' => 1, 'failed' => 0 })
    expect(data['stats']['last_failure']).to include('event' => 'QualifiedLead', 'error' => 'Invalid event name')
  end
end
