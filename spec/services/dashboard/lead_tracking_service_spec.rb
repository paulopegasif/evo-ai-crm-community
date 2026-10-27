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

  it 'labels an ad that is not synced yet by its id' do
    lead({ 'utm_source' => 'meta_ads', 'ad_id' => '120200000000001' })

    expect(campaign('Anúncio 120200000000001')).to include(leads: 1, spend: nil, cpl: nil)
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

    expect(campaign('search-botox')).to include(leads: 2, source: 'google')
    expect(result[:sources].find { |s| s[:name] == 'google' }[:leads]).to eq(2)
  end

  it 'returns empty sources and campaigns for a period without data, with no placeholder channels' do
    data = result

    expect(data[:sources]).to eq([])
    expect(data[:campaigns]).to eq([])
    expect(data[:kpis]).to include(ad_spend: 0.0, avg_cpl: nil, has_ad_spend: false)
  end
end
