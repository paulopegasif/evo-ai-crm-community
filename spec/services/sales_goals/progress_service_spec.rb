# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe SalesGoals::ProgressService do
  include SalesFixtures

  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:month) { Date.new(2026, 11, 1) }
  let(:goal) { SalesGoal.create!(month: month, amount: 20_000) }

  before { allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo') }

  it 'calcula percentual, falta e ritmo com 6 dias restantes contando hoje' do
    create_sale(amount: 12_400, sold_at: zone.local(2026, 11, 10, 10))
    result = described_class.new(month: month, goal: goal, today: Date.new(2026, 11, 25)).call
    expect(result).to include(sold: 12_400.0, percent: 62.0, remaining: 7600.0, days_left: 6, goal_reached: false)
    expect(result[:daily_pace]).to eq(1266.67)
  end

  it 'no último dia do mês o ritmo é tudo o que falta' do
    create_sale(amount: 19_100, sold_at: zone.local(2026, 11, 3, 10))
    result = described_class.new(month: month, goal: goal, today: Date.new(2026, 11, 30)).call
    expect(result[:daily_pace]).to eq(900.0)
  end

  it 'meta batida tem ritmo zero e mostra o excedente' do
    create_sale(amount: 21_000, sold_at: zone.local(2026, 11, 3, 10))
    result = described_class.new(month: month, goal: goal, today: Date.new(2026, 11, 20)).call
    expect(result).to include(goal_reached: true, daily_pace: 0.0, surplus: 1000.0, remaining: 0.0)
  end

  it 'venda cancelada sai do progresso' do
    sale = create_sale(amount: 5000, sold_at: zone.local(2026, 11, 3, 10))
    sale.cancel!
    expect(described_class.new(month: month, goal: goal, today: Date.new(2026, 11, 20)).call[:sold]).to eq(0.0)
  end

  it 'considera só o vendedor informado' do
    ana = create_user('Ana')
    create_sale(amount: 300, seller: ana, sold_at: zone.local(2026, 11, 3, 10))
    create_sale(amount: 700, sold_at: zone.local(2026, 11, 3, 10))
    result = described_class.new(month: month, seller: ana, today: Date.new(2026, 11, 20)).call
    expect(result).to include(sold: 300.0, goal: nil, percent: nil, daily_pace: nil)
  end
end
