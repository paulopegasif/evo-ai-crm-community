# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Lead list and journey' do
  let(:user) { User.create!(email: "pro-#{SecureRandom.hex(3)}@example.com", name: 'Thais') }

  before do
    MetaAds::Campaign.create!(meta_id: '6001', ad_account_id: 'act_1', name: 'Botox Outubro')
    MetaAds::Ad.create!(meta_id: '8001', meta_campaign_id: '6001', name: 'Vídeo A')
    MetaAds::InsightDaily.create!(meta_ad_id: '8001', meta_campaign_id: '6001', date: 2.days.ago.in_time_zone('America/Sao_Paulo').to_date,
                                  spend: 60, conversations: 20)
  end

  let!(:ad_lead) do
    Contact.create!(name: 'Lead Anúncio', phone_number: '+5561911111111', created_at: 2.days.ago,
                    additional_attributes: { 'utm_source' => 'meta_ads', 'ad_id' => '8001' })
  end
  let!(:organic) { Contact.create!(name: 'Lead Orgânico', phone_number: '+5561922222222', created_at: 1.day.ago) }

  let(:params) { { since: 10.days.ago.to_i.to_s, until: Time.current.to_i.to_s } }

  it 'lists leads with the estimated cost of the ad on the day of entry' do
    Appointment.create!(title: 'Avaliação', start_time: 1.day.ago, end_time: 1.day.ago + 1.hour, user: user,
                        contact: ad_lead, status: 'attended', price: 1200)

    data = Dashboard::LeadListService.new(params: params.merge(sort: 'revenue')).call
    row = data[:leads].first

    expect(data[:meta][:total_count]).to eq(2)
    expect(row).to include(name: 'Lead Anúncio', campaign_name: 'Botox Outubro', ad_name: 'Vídeo A',
                           estimated_cost: 3.0, cost_basis: 'ad_day', revenue: 1200.0, won: true)
    expect(data[:leads].last).to include(name: 'Lead Orgânico', estimated_cost: nil)
  end

  it 'filters by search term and funnel step, counting steps over the searched rows' do
    Appointment.create!(title: 'Avaliação', start_time: 1.day.ago, end_time: 1.day.ago + 1.hour, user: user,
                        contact: ad_lead, status: 'scheduled')

    by_name = Dashboard::LeadListService.new(params: params.merge(q: 'organico')).call
    expect(by_name[:leads].map { |r| r[:name] }).to eq(['Lead Orgânico'])

    by_phone = Dashboard::LeadListService.new(params: params.merge(q: '1111')).call
    expect(by_phone[:leads].map { |r| r[:name] }).to eq(['Lead Anúncio'])

    not_scheduled = Dashboard::LeadListService.new(params: params.merge(step: 'not_scheduled')).call
    expect(not_scheduled[:leads].map { |r| r[:name] }).to eq(['Lead Orgânico'])
    expect(not_scheduled[:meta][:step_counts]).to include('all' => 2, 'not_scheduled' => 1, 'scheduled' => 1, 'won' => 0)
  end

  it 'exports the list as CSV' do
    csv = Dashboard::LeadListService.new(params: params).to_csv
    expect(csv.lines.first).to include('Nome;Telefone;Entrada')
    expect(csv.lines.size).to eq(3)
  end

  it 'builds the journey with origin, cost, revenue and ROI' do
    Appointment.create!(title: 'Avaliação', start_time: 1.day.ago, end_time: 1.day.ago + 1.hour, user: user,
                        contact: ad_lead, status: 'attended', price: 1200)

    journey = Dashboard::LeadJourneyService.new(contact: ad_lead).call

    expect(journey[:origin]).to include(campaign_name: 'Botox Outubro', ad_name: 'Vídeo A', estimated_cost: 3.0)
    expect(journey[:summary]).to include(estimated_cost: 3.0, revenue: 1200.0, roi: 400.0)
    expect(journey[:events].map { |e| e[:type] }).to eq(%w[lead_created appointment sale])
  end
end
