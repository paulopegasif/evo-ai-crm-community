# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
RSpec.describe 'External Lead Tracking End-to-End Integration', type: :request do
  let!(:user) { User.create!(email: 'dra.camila@lumombeauty.com.br', name: 'Dra. Camila') }
  let!(:pipeline) { Pipeline.create!(name: 'Jornada do Paciente', pipeline_type: 'sales', created_by: user) }
  let!(:stage_won) { PipelineStage.create!(pipeline: pipeline, name: '5. Fechado & Procedimento Realizado', position: 5, stage_type: 'completed') }

  before do
    MetaAds::Campaign.create!(meta_id: '6001', ad_account_id: 'act_lumom', name: 'Campanha Tráfego Endolaser')
    MetaAds::Ad.create!(meta_id: '120260810960180456', meta_campaign_id: '6001', name: 'Anúncio Endolaser 01')
    MetaAds::InsightDaily.create!(meta_ad_id: '120260810960180456', meta_campaign_id: '6001', date: 2.days.ago.to_date, spend: 300.0)
  end

  it 'syncs a lead from external CRM with ad attribution and reflects on Lead Tracking dashboard' do
    payload = {
      source: 'bitrix24',
      external_id: '272315',
      contact: {
        name: 'Cássia Rodrigues',
        phone_number: '+5561985702132',
        email: 'cassia@example.com',
        created_at: 2.days.ago.iso8601
      },
      referral: {
        source_id: '120260810960180456',
        source_type: 'ad',
        source_url: 'https://fb.me/reel',
        headline: 'Chamar no WhatsApp',
        ctwa_clid: 'AfheykVY92LBMq9...'
      },
      deal: {
        pipeline_id: pipeline.id,
        stage_id: stage_won.id,
        value: 1800.00
      },
      appointments: [
        {
          external_id: 'deal_272315_eval',
          start_time: 1.day.ago.iso8601,
          duration_minutes: 60,
          status: 'attended',
          price: 1800.00,
          title: 'Avaliação Endolaser - Cássia Rodrigues',
          professional_email: user.email
        }
      ]
    }

    # 1. Sync external lead
    sync_result = ExternalLeads::SyncService.new(payload).perform
    expect(sync_result[:success]).to be(true)
    expect(sync_result[:contact][:action]).to eq('created')
    expect(sync_result[:pipeline_item][:action]).to eq('created')
    expect(sync_result[:appointments].first[:action]).to eq('created')

    # 2. Query Dashboard::LeadTrackingService
    dashboard_params = {
      since: 5.days.ago.to_i.to_s,
      until: Time.current.to_i.to_s
    }
    dashboard = Dashboard::LeadTrackingService.new(params: dashboard_params).call

    # 3. Verify Campaign Attribution
    campaign = dashboard[:campaigns].find { |c| c[:meta_campaign_id] == '6001' }
    expect(campaign).to be_present
    expect(campaign[:name]).to eq('Campanha Tráfego Endolaser')
    expect(campaign[:leads]).to eq(1)
    expect(campaign[:scheduled]).to eq(1)
    expect(campaign[:attended]).to eq(1)
    expect(campaign[:won]).to eq(1)
    expect(campaign[:revenue]).to eq(1800.00)
    expect(campaign[:spend]).to eq(300.00)
    expect(campaign[:roas]).to eq(6.0)

    # 4. Verify Funnel
    funnel = dashboard[:funnel].index_by { |s| s[:key] }
    expect(funnel['leads'][:count]).to eq(1)
    expect(funnel['scheduled'][:count]).to eq(1)
    expect(funnel['attended'][:count]).to eq(1)
    expect(funnel['won'][:count]).to eq(1)
  end
end
# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
