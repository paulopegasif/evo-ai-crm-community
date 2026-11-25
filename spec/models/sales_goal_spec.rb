# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe SalesGoal, type: :model do
  include SalesFixtures

  it 'normaliza o mês para o dia 1' do
    goal = described_class.create!(month: Date.new(2026, 11, 17), amount: 100)
    expect(goal.month).to eq(Date.new(2026, 11, 1))
  end

  it 'permite uma única meta geral por mês' do
    described_class.create!(month: Date.new(2026, 11, 1), amount: 100)
    expect(described_class.new(month: Date.new(2026, 11, 5), amount: 200)).not_to be_valid
  end

  it 'permite uma meta por vendedor por mês, independente da geral' do
    ana = create_user('Ana')
    described_class.create!(month: Date.new(2026, 11, 1), amount: 100)
    described_class.create!(month: Date.new(2026, 11, 1), amount: 50, user: ana)
    expect(described_class.new(month: Date.new(2026, 11, 1), amount: 70, user: ana)).not_to be_valid
  end

  it 'exige valor maior que zero' do
    expect(described_class.new(month: Date.new(2026, 11, 1), amount: 0)).not_to be_valid
  end
end
