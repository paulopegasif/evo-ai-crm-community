# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe DailySummary::MessageBuilder do
  include SalesFixtures

  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:today) { Date.new(2026, 11, 25) }

  before { allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo') }

  it 'traz vendas e meta do dia' do
    create_sale(amount: 1000, sold_at: zone.local(2026, 11, 25, 10))
    create_sale(amount: 240, sold_at: zone.local(2026, 11, 25, 11))
    create_sale(amount: 11_160, sold_at: zone.local(2026, 11, 3, 11))
    SalesGoal.create!(month: today, amount: 20_000)

    text = described_class.new(date: today).call
    expect(text).to include('*Resumo do dia — quarta-feira, 25/11*')
    expect(text).to include('💰 Vendas: 2 (R$ 1.240,00)')
    expect(text).to include('🎯 Meta do mês: 62,0% · faltam R$ 7.600,00 (≈ R$ 1.266,67/dia)')
    expect(text).not_to include('Oportunidades')
  end

  it 'sem vendas destaca oportunidades e marca teste' do
    _, stages = create_sales_pipeline(user: create_user('Dono'))
    card = PipelineItem.create!(pipeline: stages[:new].pipeline, pipeline_stage: stages[:proposal], contact: create_contact)
    card.update_columns(entered_at: 5.days.ago, created_at: 5.days.ago)
    card.stage_movements.update_all(created_at: 5.days.ago)

    text = described_class.new(date: today, test: true).call
    expect(text).to start_with('[TESTE] ')
    expect(text).to include('💰 Nenhuma venda hoje.')
    expect(text).to include('👉 Oportunidades em aberto: 1 propostas paradas.')
  end
end
