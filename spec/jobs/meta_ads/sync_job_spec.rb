# frozen_string_literal: true

require 'rails_helper'
require 'webmock/rspec'

RSpec.describe MetaAds::SyncJob do
  let(:graph) { "https://graph.facebook.com/#{MetaAds::GraphClient::DEFAULT_VERSION}" }
  let(:account) { 'act_1234567890' }
  let(:token) { 'EAABwzLixnjYBOtestTOKENvalue9xyz9' }
  let(:today) { Time.current.in_time_zone('America/Sao_Paulo').to_date }

  let(:campaigns) do
    [{ id: '6001', name: 'Botox Outubro', status: 'ACTIVE', effective_status: 'ACTIVE', objective: 'OUTCOME_ENGAGEMENT' },
     { id: '6002', name: 'Harmonização', status: 'PAUSED', effective_status: 'PAUSED', objective: 'OUTCOME_LEADS' }]
  end
  let(:adsets) { [{ id: '7001', name: 'Mulheres 25-45', status: 'ACTIVE', effective_status: 'ACTIVE', campaign_id: '6001' }] }
  let(:ads) do
    [{ id: '8001', name: 'Vídeo A', status: 'ACTIVE', effective_status: 'ACTIVE', adset_id: '7001', campaign_id: '6001' },
     { id: '8002', name: 'Carrossel B', status: 'ACTIVE', effective_status: 'ACTIVE', adset_id: '7001', campaign_id: '6001' }]
  end
  let(:insights) do
    [{ ad_id: '8001', campaign_id: '6001', spend: '120.50', impressions: '10000', reach: '8000', clicks: '300',
       date_start: (today - 1).iso8601 },
     { ad_id: '8002', campaign_id: '6001', spend: '79.50', impressions: '5000', reach: '4000', clicks: '150',
       date_start: (today - 1).iso8601 }]
  end

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('META_GRAPH_API_VERSION', nil).and_return(nil)
    allow(GlobalConfigService).to receive(:load).with('META_APP_SECRET', nil).and_return(nil)
    allow(MetaAds::SyncLock).to receive_messages(acquire: true, release: true, locked?: false)
    connect_integration
    stub_edges
  end

  def connect_integration
    MetaAds::Integration.connect!(
      ad_account_id: account, access_token: token,
      account: MetaAds::ConnectionService::Result.new(account_name: 'Lumom', currency: 'BRL',
                                                      timezone_name: 'America/Sao_Paulo')
    )
  end

  def json(body)
    { status: 200, body: body.to_json, headers: { 'Content-Type' => 'application/json' } }
  end

  def stub_edges
    stub_request(:get, "#{graph}/#{account}/campaigns").with(query: hash_including({})).to_return(json(data: campaigns))
    stub_request(:get, "#{graph}/#{account}/adsets").with(query: hash_including({})).to_return(json(data: adsets))
    stub_request(:get, "#{graph}/#{account}/ads").with(query: hash_including({})).to_return(json(data: ads))
    stub_request(:get, "#{graph}/#{account}/insights").with(query: hash_including({})).to_return(json(data: insights))
  end

  def integration
    MetaAds::Integration.current
  end

  it 'imports the structure and daily insights and updates the status' do
    described_class.perform_now

    expect(MetaAds::Campaign.pluck(:meta_id)).to contain_exactly('6001', '6002')
    expect(MetaAds::Adset.first.meta_campaign_id).to eq('6001')
    expect(MetaAds::Ad.find_by(meta_id: '8002')).to have_attributes(meta_adset_id: '7001', meta_campaign_id: '6001')
    expect(MetaAds::InsightDaily.sum(:spend)).to eq(200.0)
    expect(MetaAds::InsightDaily.find_by(meta_ad_id: '8001')).to have_attributes(impressions: 10_000, clicks: 300,
                                                                                 currency: 'BRL')
    expect(integration.settings).to include('connection_status' => 'connected', 'last_error' => nil)
    expect(integration.settings['last_synced_at']).to be_present
    expect(integration.settings['counts']).to eq('campaigns' => 2, 'adsets' => 1, 'ads' => 2)
  end

  it 'imports 90 days of history on the first sync and 7 days afterwards' do
    described_class.perform_now
    first_ranges = WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                                           .select { |sig| sig.uri.path.end_with?('/insights') }
                                           .map { |sig| JSON.parse(sig.uri.query_values['time_range']) }
    expect(first_ranges.map { |r| r['since'] }.min).to eq((today - 90).iso8601)

    WebMock::RequestRegistry.instance.reset!
    described_class.perform_now
    ranges = WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                                     .select { |sig| sig.uri.path.end_with?('/insights') }
                                     .map { |sig| JSON.parse(sig.uri.query_values['time_range']) }
    expect(ranges).to eq([{ 'since' => (today - 7).iso8601, 'until' => today.iso8601 }])
  end

  it 'updates renamed objects and revised spend without duplicating rows' do
    described_class.perform_now
    campaigns.first[:name] = 'Botox Novembro'
    insights.first[:spend] = '130.00'
    stub_edges

    described_class.perform_now

    expect(MetaAds::Campaign.count).to eq(2)
    expect(MetaAds::Campaign.find_by(meta_id: '6001').name).to eq('Botox Novembro')
    expect(MetaAds::InsightDaily.count).to eq(2)
    expect(MetaAds::InsightDaily.find_by(meta_ad_id: '8001').spend).to eq(130.0)
  end

  it 'follows pagination until the last page' do
    next_url = "#{graph}/#{account}/campaigns?after=cursor2&access_token=#{token}"
    stub_request(:get, "#{graph}/#{account}/campaigns").with(query: hash_including('limit' => '500'))
                                                       .to_return(json(data: [campaigns.first], paging: { next: next_url }))
    stub_request(:get, "#{graph}/#{account}/campaigns").with(query: hash_including('after' => 'cursor2'))
                                                       .to_return(json(data: [campaigns.last]))

    described_class.perform_now

    expect(MetaAds::Campaign.pluck(:meta_id)).to contain_exactly('6001', '6002')
  end

  it 'marks the token invalid, keeps data and stops automatic syncs on OAuthException 190' do
    described_class.perform_now
    stub_request(:get, "#{graph}/#{account}/campaigns").with(query: hash_including({}))
                                                       .to_return(status: 400, body: { error: { message: 'Token revoked', code: 190 } }.to_json,
                                                                  headers: { 'Content-Type' => 'application/json' })

    described_class.perform_now

    expect(integration.connection_status).to eq('token_invalid')
    expect(integration.settings.dig('last_error', 'message')).to include('Token revoked')
    expect(MetaAds::Campaign.count).to eq(2)
    expect(integration.syncable?).to be(false)
  end

  it 'records rate limits without invalidating the connection' do
    stub_request(:get, "#{graph}/#{account}/campaigns").with(query: hash_including({}))
                                                       .to_return(status: 400, body: { error: { message: 'Too many calls', code: 17 } }.to_json,
                                                                  headers: { 'Content-Type' => 'application/json' })

    described_class.perform_now

    expect(integration.connection_status).to eq('connected')
    expect(integration.settings.dig('last_error', 'code')).to eq(17)
    expect(integration.syncable?).to be(true)
  end

  it 'does not call Meta without a connected integration' do
    Integrations::Hook.where(app_id: 'meta_ads').destroy_all
    WebMock::RequestRegistry.instance.reset!

    described_class.perform_now

    expect(WebMock).not_to have_requested(:get, /graph\.facebook\.com/)
  end

  it 'skips when another sync holds the lock' do
    allow(MetaAds::SyncLock).to receive(:acquire).and_return(false)

    described_class.perform_now

    expect(MetaAds::Campaign.count).to eq(0)
  end
end
