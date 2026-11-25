# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')
require Rails.root.join('spec/support/business_assistant_helpers')

RSpec.describe 'Assistant::V1 análises', type: :request do
  include SalesFixtures
  include BusinessAssistantHelpers

  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let!(:settings) { configure_assistant! }
  let(:headers) { assistant_headers(settings) }

  before { allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo') }

  def at(year, month, day, hour = 12)
    zone.local(year, month, day, hour)
  end

  def analysis(name, params = {})
    get "/assistant/v1/analytics/#{name}", params: params, headers: headers
    expect(response).to have_http_status(:ok), response.body
    assistant_data['data']
  end

  describe 'month_projection' do
    it 'projeta pela média do mês quando há pouco histórico (exemplo da spec)' do
      travel_to(at(2026, 11, 15, 18)) do
        SalesGoal.create!(month: Date.new(2026, 11, 1), amount: 20_000)
        create_sale(amount: 3000, sold_at: at(2026, 11, 3))
        create_sale(amount: 3000, sold_at: at(2026, 11, 9))
        create_sale(amount: 3000, sold_at: at(2026, 11, 15, 10))

        data = analysis('month_projection')
        expect(data).to include('method' => 'linear', 'sold' => 9000.0, 'projected' => 18_000.0, 'goal' => 20_000.0,
                                'projected_gap_to_goal' => -2000.0, 'remaining_to_goal' => 11_000.0,
                                'daily_needed' => 687.5, 'days_remaining_after_today' => 15)
      end
    end

    it 'usa o ritmo por dia da semana quando há histórico' do
      travel_to(at(2026, 11, 15, 18)) do
        mondays = [[9, 21], [9, 28], [10, 5], [10, 12], [10, 19], [10, 26], [11, 2], [11, 9]]
        mondays.each { |m, d| create_sale(amount: 80, sold_at: at(2026, m, d)) }
        [[10, 6], [10, 13]].each { |m, d| create_sale(amount: 40, sold_at: at(2026, m, d)) }

        data = analysis('month_projection')
        # Mês: 160 vendidos; restam 3 segundas (média 80) e 2 terças (média 10).
        expect(data).to include('method' => 'weekday_pace', 'sold' => 160.0, 'projected' => 420.0, 'goal' => nil)
      end
    end
  end

  it 'compare: período atual contra o anterior' do
    travel_to(at(2026, 11, 25, 18)) do
      create_sale(amount: 300, sold_at: at(2026, 11, 24))
      create_sale(amount: 100, sold_at: at(2026, 11, 23))
      create_sale(amount: 200, sold_at: at(2026, 11, 15))

      data = analysis('compare', days: 7)
      expect(data['current']['metrics']).to include('sales_count' => 2, 'sales_total' => 400.0)
      expect(data['previous']['metrics']).to include('sales_count' => 1, 'sales_total' => 200.0)
      expect(data['variation']['sales_total']).to eq('absolute' => 200.0, 'pct' => 100.0)
    end
  end

  describe 'campanhas e simulação' do
    around { |example| travel_to(at(2026, 11, 25, 18)) { example.run } }

    before do
      create_meta_ads_tables!
      conn = ActiveRecord::Base.connection
      conn.execute("INSERT INTO meta_campaigns (meta_id, name) VALUES ('c1', 'Botox Novembro')")
      conn.execute("INSERT INTO meta_ads (meta_id, meta_campaign_id) VALUES ('a1', 'c1')")
      insert_insight(ad: 'a1', campaign: 'c1', date: '2026-11-20', spend: 100, leads: 3)

      by_ad = create_contact('Ana').tap { |c| c.update!(additional_attributes: { 'ad_id' => 'a1' }) }
      create_contact('Bia').tap { |c| c.update!(additional_attributes: { 'utm_campaign' => 'botox novembro' }) }
      create_sale(amount: 500, contact: by_ad, sold_at: at(2026, 11, 21))
      create_sale(amount: 50, contact: create_contact('Sem origem'), sold_at: at(2026, 11, 22))
    end

    it 'cruza gasto com leads e vendas do CRM' do
      data = analysis('campaigns', days: 30)
      expect(data['campaigns'].first).to include('name' => 'Botox Novembro', 'spend' => 100.0, 'crm_leads' => 2,
                                                 'sales_count' => 1, 'revenue' => 500.0, 'cost_per_lead' => 50.0,
                                                 'roas' => 5.0, 'lead_to_sale_pct' => 50.0)
      expect(data['unattributed']).to include('sales_count' => 1, 'revenue' => 50.0)
      expect(assistant_data['coverage']['ads_data_available']).to be(true)
    end

    it 'simula orçamento como estimativa linear' do
      data = analysis('budget_simulation', days: 30, budget: '1000')
      expect(data).to include('estimate' => true, 'estimated_leads' => 20.0, 'estimated_sales' => 10.0,
                              'estimated_revenue' => 5000.0, 'estimated_roas' => 5.0, 'low_confidence' => true)
    end

    it 'recusa orçamento inválido' do
      get '/assistant/v1/analytics/budget_simulation', params: { budget: 'muito' }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'campanhas sem integração Meta' do
    expect(analysis('campaigns')).to eq('ads_data_available' => false, 'campaigns' => [])
  end

  it 'funnel: etapas atingidas, ganhos, perdidos e passagem entre etapas' do
    user = create_user('Dono')
    _pipeline, stages = create_sales_pipeline(user: user)
    won = PipelineItem.create!(pipeline: stages[:new].pipeline, pipeline_stage: stages[:new], contact: create_contact('A'))
    won.update!(pipeline_stage: stages[:proposal])
    won.update!(pipeline_stage: stages[:won], completed_at: 3.days.from_now)
    PipelineItem.create!(pipeline: stages[:new].pipeline, pipeline_stage: stages[:proposal], contact: create_contact('B'))
    lost = PipelineItem.create!(pipeline: stages[:new].pipeline, pipeline_stage: stages[:new], contact: create_contact('C'))
    lost.update!(pipeline_stage: stages[:lost])

    funnel = analysis('funnel')['pipelines'].first
    expect(funnel).to include('items_created' => 3, 'won' => 1, 'lost' => 1, 'win_rate_pct' => 33.3)
    expect(funnel['stages'].map { |s| [s['name'], s['reached']] }).to eq([['Novo', 3], ['Proposta', 2], ['Ganho', 1]])
    expect(funnel['stages'].last['conversion_from_previous_pct']).to eq(50.0)
    expect(funnel['avg_days_to_win']).to be_within(0.1).of(3.0)
  end

  it 'seasonality: melhor dia da semana e horário' do
    travel_to(at(2026, 11, 25, 18)) do
      create_sale(amount: 500, sold_at: at(2026, 11, 24, 10)) # terça 10h
      create_sale(amount: 300, sold_at: at(2026, 11, 17, 10)) # terça 10h
      create_sale(amount: 100, sold_at: at(2026, 11, 20, 16)) # sexta 16h

      data = analysis('seasonality', days: 30)
      expect(data).to include('best_weekday' => 'terça', 'best_hour' => 10)
      tuesday = data['by_weekday'].find { |row| row['weekday'] == 'terça' }
      expect(tuesday).to include('count' => 2, 'total' => 800.0)
    end
  end

  it 'customer_health: recorrência, novos e clientes em risco' do
    travel_to(at(2026, 11, 25, 18)) do
      loyal = create_contact('Fiel')
      [at(2026, 8, 1), at(2026, 8, 31), at(2026, 9, 30)].each { |t| create_sale(amount: 200, contact: loyal, sold_at: t) }
      steady = create_contact('Em dia')
      [at(2026, 11, 1), at(2026, 11, 20)].each { |t| create_sale(amount: 100, contact: steady, sold_at: t) }
      create_sale(amount: 80, contact: create_contact('Novo'), sold_at: at(2026, 11, 22))

      data = analysis('customer_health', days: 30)
      expect(data).to include('total_customers' => 3, 'recurring_customers' => 2, 'recurring_pct' => 66.7,
                              'new_customers_in_period' => 2, 'inactive_customers' => 1)
      expect(data['at_risk'].map { |c| c['name'] }).to eq(['Fiel'])
      expect(data['at_risk'].first).to include('usual_interval_days' => 30.0, 'days_since_last_purchase' => 56)
    end
  end
end
