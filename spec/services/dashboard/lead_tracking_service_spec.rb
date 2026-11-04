# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dashboard::LeadTrackingService do
  let(:professional) { User.create!(email: "pro-#{SecureRandom.hex(4)}@example.com", name: 'Dra. Ana') }
  let(:params) { { since: 10.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  def lead(attrs = {}, custom: {})
    Contact.create!(name: "Lead #{SecureRandom.hex(3)}", additional_attributes: attrs, custom_attributes: custom)
  end

  def attended(contact, price)
    Appointment.create!(title: 'Botox', start_time: 2.days.ago, end_time: 2.days.ago + 1.hour, user: professional,
                        contact: contact, status: 'attended', price: price, category: 'Geral')
  end

  def result
    described_class.new(params: params).call
  end

  def campaign(name)
    result[:campaigns].find { |c| c[:name] == name }
  end

  before do
    MetaAds::Campaign.create!(meta_id: '6001', ad_account_id: 'act_1', name: 'Botox Outubro')
    MetaAds::Ad.create!(meta_id: '8001', meta_campaign_id: '6001', name: 'Vídeo A')
    MetaAds::Ad.create!(meta_id: '8002', meta_campaign_id: '6001', name: 'Carrossel B')
  end

  it 'groups leads from different ads of the same campaign' do
    4.times { lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8001' }) }
    3.times { lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8002' }) }

    expect(campaign('Botox Outubro')).to include(leads: 7, source: 'Meta Ads', meta_campaign_id: '6001')
  end

  it 'computes CPL, CAC and ROAS from the period spend' do
    leads = Array.new(20) { lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8001' }) }
    leads.first(4).each { |c| attended(c, 1500) }
    MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: 3.days.ago.to_date, spend: 600)
    MetaAds::InsightDaily.create!(meta_ad_id: '8002', meta_campaign_id: '6001', date: 2.days.ago.to_date, spend: 400)
    MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: 40.days.ago.to_date, spend: 999)

    expect(campaign('Botox Outubro')).to include(
      leads: 20, won: 4, revenue: 6000.0, spend: 1000.0, cpl: 50.0, cac: 250.0, roas: 6.0
    )
    expect(result[:kpis]).to include(ad_spend: 1000.0, ad_leads: 20, avg_cpl: 50.0, has_ad_spend: true)
  end

  it 'shows campaigns with spend and no leads with nil ratios' do
    MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: 1.day.ago.to_date, spend: 300)

    expect(campaign('Botox Outubro')).to include(leads: 0, spend: 300.0, cpl: nil, cac: nil, roas: 0.0)
  end

  it 'groups ads outside the synced catalog in a single row' do
    lead({ 'utm_source' => 'meta_ads', 'ad_id' => '120200000000001' })
    lead({ 'utm_source' => 'meta_ads', 'ad_id' => '120200000000002' })

    expect(campaign('Anúncio removido ou de outra conta')).to include(leads: 2, source: 'Meta Ads', spend: nil, cpl: nil)
  end

  it 'counts Meta leads without an identified ad under "Anúncio não identificado"' do
    lead({ 'utm_source' => 'meta_ads', 'attribution_channel' => 'external_fallback' })

    expect(campaign('Anúncio não identificado')).to include(leads: 1, source: 'Meta Ads')
  end

  it 'groups leads without origin under "Sem campanha" and never presumes a source' do
    lead
    lead({ 'utm_campaign' => 'harmonizacao' })

    expect(campaign('Sem campanha')).to include(leads: 1, source: 'Não informada')
    expect(campaign('harmonizacao')).to include(leads: 1, source: 'Não informada', spend: nil)
    expect(result[:sources].map { |s| s[:name] }).to contain_exactly('Não informada')
  end

  it 'reads utm attributes from additional_attributes and custom_attributes consistently' do
    lead({ 'utm_source' => 'google', 'utm_campaign' => 'search-botox' })
    lead({}, custom: { 'utm_source' => 'google', 'utm_campaign' => 'search-botox' })

    expect(campaign('search-botox')).to include(leads: 2, source: 'Google')
    expect(result[:sources].find { |s| s[:name] == 'Google' }[:leads]).to eq(2)
  end

  it 'returns empty sources and campaigns for a period without data, with no placeholder channels' do
    data = result

    expect(data[:sources]).to eq([])
    expect(data[:campaigns]).to eq([])
    expect(data[:kpis]).to include(ad_spend: 0.0, avg_cpl: nil, has_ad_spend: false)
  end

  def appointment(contact, status, price: 0, start_time: 2.days.ago, category: 'Geral', user: professional)
    Appointment.create!(title: 'Consulta', start_time: start_time, end_time: start_time + 1.hour, user: user,
                        contact: contact, status: status, price: price, category: category)
  end

  describe 'lead funnel' do
    it 'counts people, so every stage is a subset of the previous one' do
      leads = Array.new(10) { lead }
      leads.first(6).each { |c| appointment(c, 'scheduled') }
      appointment(leads[0], 'scheduled') # second appointment of the same lead
      leads.first(3).each { |c| appointment(c, 'attended', price: 500) }
      appointment(leads[3], 'attended', price: 0) # attended a free evaluation: not a sale
      appointment(leads[4], 'cancelled')

      funnel = result[:funnel].index_by { |s| s[:key] }

      expect(funnel.transform_values { |s| s[:count] })
        .to eq('leads' => 10, 'qualified' => 6, 'scheduled' => 6, 'attended' => 4, 'won' => 3)
      expect(funnel['attended']).to include(percentage: 40.0, step_rate: 66.7)
      expect(funnel['won']).to include(percentage: 30.0, step_rate: 75.0)
    end

    it 'ignores appointments of contacts created before the period' do
      old = lead
      old.update_columns(created_at: 60.days.ago)
      appointment(old, 'attended', price: 900)
      lead

      kpis = result[:kpis]

      expect(kpis).to include(total_leads: 1, total_scheduled: 0, total_won: 0, scheduling_rate: 0.0)
      # The agenda still reflects the visit and its revenue.
      expect(kpis).to include(appointments_attended: 1, total_revenue: 900.0)
    end

    it 'returns nil rates when there are no leads' do
      expect(result[:kpis]).to include(scheduling_rate: nil, conversion_rate: nil)
      expect(result[:funnel].map { |s| s[:percentage] }).to all(be_nil)
    end

    it 'qualifies only leads that scheduled or reached a stage flagged as qualifying' do
      pipeline = Pipeline.create!(name: 'Comercial', created_by: professional)
      stage_entry = PipelineStage.create!(pipeline: pipeline, name: 'Novos Leads', position: 1, stage_type: :active)
      stage_triage = PipelineStage.create!(pipeline: pipeline, name: '1ª tentativa de ligação', position: 2, stage_type: :active)
      stage_eval = PipelineStage.create!(pipeline: pipeline, name: 'Avaliação Agendada', position: 3, stage_type: :active,
                                         counts_as_qualified: true)
      stage_lost = PipelineStage.create!(pipeline: pipeline, name: 'Perdido', position: 7, stage_type: :cancelled)

      PipelineItem.create!(pipeline: pipeline, pipeline_stage: stage_entry, contact: lead) # not qualified
      PipelineItem.create!(pipeline: pipeline, pipeline_stage: stage_lost, contact: lead) # not qualified
      PipelineItem.create!(pipeline: pipeline, pipeline_stage: stage_triage, contact: lead) # contact attempt: not qualified
      PipelineItem.create!(pipeline: pipeline, pipeline_stage: stage_eval, contact: lead) # flagged stage: qualified
      appointment(lead, 'scheduled') # scheduled: qualified

      expect(result[:kpis]).to include(total_leads: 5, total_qualified: 2, total_scheduled: 1)
    end
  end

  describe 'period agenda' do
    it 'computes the show rate over finished appointments only, and confirmed separately from pending' do
      contact = lead
      appointment(contact, 'attended', price: 300)
      appointment(contact, 'no_show')
      appointment(contact, 'confirmed', start_time: 1.day.from_now.beginning_of_day)
      appointment(contact, 'scheduled', start_time: 1.day.from_now.beginning_of_day)

      expect(result[:kpis]).to include(
        total_appointments: 4, total_confirmed: 1, total_pending: 2, show_rate: 50.0,
        total_revenue: 300.0, paid_appointments: 1, average_ticket: 300.0
      )
    end

    it 'leaves the show rate of a professional without finished appointments empty instead of 100%' do
      appointment(lead, 'scheduled', start_time: 1.day.from_now.beginning_of_day)

      expect(result[:professionals].first).to include(total: 1, pending: 1, show_rate: nil)
    end

    it 'reports the revenue share of each procedure next to its volume share' do
      contact = lead
      appointment(contact, 'attended', price: 900, category: 'Botox')
      appointment(contact, 'attended', price: 100, category: 'Avaliação')
      appointment(contact, 'scheduled', category: 'Avaliação', start_time: 1.day.from_now.beginning_of_day)

      categories = result[:categories].index_by { |c| c[:name] }

      expect(categories['Botox']).to include(count: 1, revenue: 900.0, share_percentage: 33.3, revenue_share: 90.0)
      expect(categories['Avaliação']).to include(count: 2, revenue: 100.0, share_percentage: 66.7, revenue_share: 10.0)
    end
  end

  describe 'timeline' do
    it 'buckets days in the viewer timezone and includes daily ad spend' do
      travel_to Time.utc(2026, 10, 20, 12) do
        # 01:30 UTC on the 20th is still the 19th in São Paulo.
        contact = lead
        contact.update_columns(created_at: Time.utc(2026, 10, 20, 1, 30))
        MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: Date.new(2026, 10, 19), spend: 42)

        data = described_class.new(params: params.merge(timezone: 'America/Sao_Paulo')).call
        day = data[:timeline].find { |d| d[:date] == '2026-10-19' }

        expect(day).to include(leads: 1, spend: 42.0)
        expect(data[:period][:timezone]).to eq('America/Sao_Paulo')
      end
    end

    it 'groups long periods by week and month' do
      travel_to Time.utc(2026, 10, 20, 12) do
        MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: Date.new(2026, 10, 13), spend: 10)
        MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: Date.new(2026, 10, 15), spend: 5)
        year = { since: Time.utc(2026, 1, 1, 12).to_i.to_s, until: Time.current.to_i.to_s }

        weekly = described_class.new(params: year).call
        week = weekly[:timeline].find { |p| p[:start_date] == '2026-10-12' }
        expect(weekly[:period][:granularity]).to eq('week')
        expect(week).to include(label: 'sem. 12/10', end_date: '2026-10-18', spend: 15.0)
        expect(weekly[:timeline].first[:start_date]).to eq('2026-01-01')

        monthly = described_class.new(params: year.merge(granularity: 'month')).call
        expect(monthly[:timeline].size).to eq(10)
        expect(monthly[:timeline].last).to include(label: 'out/26', start_date: '2026-10-01', end_date: '2026-10-20')
      end
    end
  end

  describe 'paid media' do
    before do
      MetaAds::Campaign.create!(meta_id: '6002', ad_account_id: 'act_1', name: 'Harmonização', effective_status: 'PAUSED')
      MetaAds::Ad.create!(meta_id: '8003', meta_campaign_id: '6002', name: 'Reels')
      MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: 2.days.ago.to_date, spend: 300,
                                    impressions: 20_000, link_clicks: 400, conversations: 100, meta_leads: 0)
      MetaAds::InsightDaily.create!(meta_ad_id: '8003', meta_campaign_id: '6002', date: 1.day.ago.to_date, spend: 200,
                                    impressions: 5_000, link_clicks: 0, conversations: 25, meta_leads: 4)
    end

    it 'reports delivery, results and cost per result' do
      expect(result[:kpis]).to include(
        ad_spend: 500.0, impressions: 25_000, link_clicks: 400, ctr: 1.6, cpc: 1.25, cpm: 20.0,
        conversations: 125, cost_per_conversation: 4.0, meta_leads: 4, cost_per_meta_lead: 125.0
      )
      expect(campaign('Harmonização')).to include(status: 'PAUSED', spend: 200.0, cpc: nil, ctr: 0.0,
                                                  conversations: 25, cost_per_conversation: 8.0)
    end

    it 'narrows leads and media to one Meta campaign' do
      2.times { lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8001' }) }
      lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8003' })
      lead

      data = described_class.new(params: params.merge(campaign_key: 'meta:6001')).call

      expect(data[:kpis]).to include(total_leads: 2, ad_spend: 300.0, conversations: 100, lead_capture_rate: 2.0, has_ad_spend: true)
      expect(data[:campaigns].map { |c| c[:name] }).to eq(['Botox Outubro'])
      expect(data[:campaigns].first).to include(leads: 2, conversations: 100, lead_capture_rate: 2.0)
      expect(data[:filter_options][:campaigns].map { |c| c[:name] }).to include('Botox Outubro', 'Harmonização', 'Sem campanha')
    end

    it 'hides paid media for a source outside Meta' do
      lead({ 'utm_source' => 'google' })
      lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8001' })

      data = described_class.new(params: params.merge(source: 'Google')).call

      expect(data[:kpis]).to include(total_leads: 1, ad_spend: 0.0, conversations: 0, cost_per_conversation: nil,
                                     has_ad_spend: false)
      expect(data[:filter_options][:sources]).to contain_exactly('Google', 'Meta Ads')
    end

    it 'adds the results to each timeline point' do
      day = result[:timeline].find { |p| p[:date] == 2.days.ago.to_date.iso8601 }

      expect(day).to include(spend: 300.0, conversations: 100, link_clicks: 400, impressions: 20_000)
    end
  end

  describe 'business indicators' do
    let(:params) { { since: 20.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

    def media(spend:, conversations:)
      MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: 5.days.ago.to_date,
                                    spend: spend, conversations: conversations)
    end

    it 'computes the cost of each funnel stage over ad leads only' do
      media(spend: 5000, conversations: 1400)
      ads = Array.new(280) { lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8001' }) }
      ads.first(60).each { |c| appointment(c, 'scheduled', start_time: 1.day.from_now) }
      ads.first(40).each { |c| appointment(c, 'attended', price: 0) }
      ads.first(20).each { |c| appointment(c, 'attended', price: 750) }
      lead # organic lead never enters the ad costs

      expect(result[:kpis]).to include(
        cost_per_conversation: 3.57, avg_cpl: 17.86, cost_per_scheduled: 83.33,
        cost_per_attended: 125.0, ad_cac: 250.0, roas: 3.0
      )
    end

    it 'excludes returning customers from the cohort' do
      lead
      lead({}, custom: { 'customer_type' => 'returning' })

      expect(result[:kpis][:total_leads]).to eq(1)
    end

    it 'reports the median days from lead to evaluation' do
      [0, 1, 2, 3, 10].each do |days|
        contact = lead
        contact.update_columns(created_at: 15.days.ago)
        appointment(contact, 'scheduled', start_time: 15.days.ago + days.days + 1.hour)
      end

      expect(result[:velocity]).to include(lead_to_evaluation_days: 2, lead_to_evaluation_count: 5)
    end

    it 'ranks ads by revenue with their spend and ratios' do
      media(spend: 600, conversations: 200)
      a = Array.new(3) { lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8001' }) }
      b = Array.new(5) { lead({ 'utm_source' => 'meta_ads', 'ad_id' => '8002' }) }
      attended(a.first, 1200)
      b.each { |c| appointment(c, 'scheduled', start_time: 1.day.from_now) }

      ads = result[:ads]
      expect(ads.first).to include(ad_id: '8001', name: 'Vídeo A', campaign_name: 'Botox Outubro', leads: 3, won: 1,
                                   revenue: 1200.0, spend: 600.0, cpl: 200.0, cac: 600.0, roas: 2.0)
      expect(ads.second).to include(ad_id: '8002', leads: 5, revenue: 0.0, spend: 0.0, cac: nil)
    end

    it 'separates past appointments without outcome from the ones still ahead' do
      contact = lead
      appointment(contact, 'scheduled', start_time: 2.days.ago)
      appointment(contact, 'confirmed', start_time: 1.day.ago)
      appointment(contact, 'scheduled', start_time: 2.days.from_now)

      data = described_class.new(params: params.merge(until: 5.days.from_now.to_i.to_s)).call
      expect(data[:kpis]).to include(total_no_outcome: 2, total_pending: 1)
      expect(data[:professionals].first).to include(no_outcome: 2, pending: 1)
      expect(data[:alerts][:no_outcome][:count]).to eq(2)
    end

    it 'lists leads without an appointment for more than N days, ignoring lost ones' do
      stale = lead
      stale.update_columns(created_at: 5.days.ago)
      fresh = lead
      fresh.update_columns(created_at: 1.day.ago)
      booked = lead
      booked.update_columns(created_at: 5.days.ago)
      appointment(booked, 'scheduled', start_time: 1.day.from_now)

      alerts = result[:alerts]
      expect(alerts[:stale_days]).to eq(3)
      expect(alerts[:stale_leads][:count]).to eq(1)
      expect(alerts[:stale_leads][:sample].first[:id]).to eq(stale.id)
    end

    it 'adds pending unlinked sales to the agenda revenue but not to the cohort' do
      UnlinkedSale.create!(source: 'bitrix24', external_id: 'deal_1', customer_name: 'Ana Paula Souza',
                           reason: 'ambiguous_name', amount: 1200, sold_at: 1.day.ago)

      kpis = result[:kpis]
      expect(kpis).to include(total_revenue: 1200.0, unlinked_sales: 1, unlinked_revenue: 1200.0, total_leads: 0)
    end

    it 'returns ctr as a number' do
      MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: 2.days.ago.to_date,
                                    spend: 10, impressions: 10_000, link_clicks: 183)

      expect(result[:kpis][:ctr]).to eq(1.83)
    end
  end
end
