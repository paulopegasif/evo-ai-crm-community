# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')
require Rails.root.join('spec/support/business_assistant_helpers')

RSpec.describe 'Assistant::V1 consultas', type: :request do
  include SalesFixtures
  include BusinessAssistantHelpers

  let!(:settings) { configure_assistant! }
  let(:headers) { assistant_headers(settings) }
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:now) { zone.local(2026, 11, 25, 15, 0) }

  around { |example| travel_to(zone.local(2026, 11, 25, 15, 0)) { example.run } }

  before { allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo') }

  def attributed_contact(name, **attrs)
    create_contact(name).tap { |c| c.update!(additional_attributes: attrs.stringify_keys) }
  end

  it 'exige o token do assistente' do
    get '/assistant/v1/sales/summary'
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'GET sales/summary' do
    it 'resume as vendas do período, sem canceladas, com dias zerados e cobertura' do
      ad_contact = attributed_contact('Ana', ad_id: '123')
      create_sale(amount: 100, sold_at: now - 1.hour, contact: ad_contact)
      create_sale(amount: 300, sold_at: zone.local(2026, 11, 24, 23, 30), contact: create_contact('Bia'))
      create_sale(amount: 999, sold_at: now - 2.hours).cancel!

      get '/assistant/v1/sales/summary', params: { days: 3 }, headers: headers
      expect(response).to have_http_status(:ok)
      data = assistant_data
      expect(data['data']).to include('count' => 2, 'total' => 400.0, 'average_ticket' => 200.0, 'cancelled_count' => 1)
      expect(data['data']['by_day']).to eq([
                                             { 'date' => '2026-11-23', 'count' => 0, 'total' => 0.0 },
                                             { 'date' => '2026-11-24', 'count' => 1, 'total' => 300.0 },
                                             { 'date' => '2026-11-25', 'count' => 1, 'total' => 100.0 }
                                           ])
      expect(data['period']).to include('from' => '2026-11-23', 'to' => '2026-11-25', 'timezone' => 'America/Sao_Paulo')
      expect(data['coverage']).to include('sales_with_source_pct' => 50.0, 'ads_data_available' => false)
      expect(data['currency']).to eq('BRL')
    end

    it 'devolve 422 para período inválido' do
      get '/assistant/v1/sales/summary', params: { period: 'ontem' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET leads/funnel' do
    it 'conta leads novos, conversão e origem, sem contatos internos' do
      converted = attributed_contact('Ana', utm_source: 'instagram')
      create_sale(amount: 50, contact: converted)
      create_contact('Bia')

      get '/assistant/v1/leads/funnel', params: { period: 'today' }, headers: headers
      funnel = assistant_data['data']
      # O contato do dono (assistente) é interno e não conta.
      expect(funnel).to include('new_leads' => 2, 'converted_leads' => 1, 'conversion_pct' => 50.0)
      expect(funnel['by_source']).to include({ 'source' => 'instagram', 'count' => 1 }, { 'source' => 'sem_origem', 'count' => 1 })
    end
  end

  describe 'clientes' do
    let!(:maria) { create_contact('Maria Souza') }
    let!(:maria2) { create_contact('Maria Lima') }
    let(:product) { Product.create!(name: 'Pacote 10 sessões', kind: 'digital') }

    before do
      create_sale(amount: 500, contact: maria, product: product, sold_at: now - 10.days)
      create_sale(amount: 200, contact: maria, sold_at: now - 2.days)
      create_sale(amount: 900, contact: maria2, sold_at: now - 60.days)
    end

    it 'busca devolve candidatos quando é ambígua' do
      get '/assistant/v1/customers/search', params: { q: 'maria' }, headers: headers
      expect(assistant_data['data']['matches']).to eq(2)
      souza = assistant_data['data']['customers'].find { |c| c['name'] == 'Maria Souza' }
      expect(souza).to include('purchases' => 2, 'total_spent' => 700.0, 'days_since_last_purchase' => 2)
    end

    it 'histórico traz compras, produtos e última compra' do
      get "/assistant/v1/customers/#{maria.id}/history", headers: headers
      history = assistant_data['data']
      expect(history['customer']).to include('purchases' => 2, 'total_spent' => 700.0)
      expect(history['sales'].first['amount']).to eq(200.0)
      expect(history['products']).to eq([{ 'name' => 'Pacote 10 sessões', 'kind' => 'digital', 'purchases' => 1,
                                           'total' => 500.0 }])
    end

    it 'histórico de cliente inexistente devolve 404' do
      get "/assistant/v1/customers/#{SecureRandom.uuid}/history", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it 'rankings: recentes, que mais gastam, mais frequentes e sumidos' do
      {
        'recent' => 'Maria Souza', 'top_spenders' => 'Maria Lima', 'most_frequent' => 'Maria Souza', 'inactive' => 'Maria Lima'
      }.each do |kind, first_name|
        get '/assistant/v1/customers/ranking', params: { kind: kind }, headers: headers
        expect(assistant_data['data']['customers'].first['name']).to eq(first_name), kind
      end
      get '/assistant/v1/customers/ranking', params: { kind: 'inactive' }, headers: headers
      expect(assistant_data['data']['customers'].size).to eq(1)
    end

    it 'ranking inválido devolve 422' do
      get '/assistant/v1/customers/ranking', params: { kind: 'vip' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET ads/spend' do
    it 'sem integração Meta, avisa que não há dados' do
      get '/assistant/v1/ads/spend', headers: headers
      expect(assistant_data['data']).to eq('ads_data_available' => false)
    end

    it 'com integração, soma gasto por dia e campanha' do
      create_meta_ads_tables!
      ActiveRecord::Base.connection.execute("INSERT INTO meta_campaigns (meta_id, name) VALUES ('c1', 'Botox Novembro')")
      insert_insight(ad: 'a1', campaign: 'c1', date: '2026-11-24', spend: 80, leads: 4)
      insert_insight(ad: 'a2', campaign: 'c1', date: '2026-11-25', spend: 20.5, conversations: 3)
      insert_insight(ad: 'a1', campaign: 'c1', date: '2026-11-10', spend: 999)

      get '/assistant/v1/ads/spend', params: { days: 2 }, headers: headers
      ads = assistant_data['data']
      expect(ads).to include('ads_data_available' => true, 'spend' => 100.5, 'meta_leads' => 4, 'conversations_started' => 3)
      expect(ads['by_day'].pluck('spend')).to eq([80.0, 20.5])
      expect(ads['by_campaign'].first).to include('name' => 'Botox Novembro', 'spend' => 100.5)
    end
  end

  describe 'GET pending' do
    it 'lista conversas aguardando resposta, sem as internas' do
      create_conversation(contact: create_contact('Cliente esperando'))
      get '/assistant/v1/pending', headers: headers
      pending = assistant_data['data']
      expect(pending['awaiting_reply']).to eq(1)
      expect(pending['awaiting_reply_list'].first['contact']).to eq('Cliente esperando')
    end
  end
end
