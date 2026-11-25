# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe Sale, type: :model do
  include SalesFixtures

  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

  before { allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo') }

  it 'exige valor maior que zero em venda manual' do
    sale = described_class.new(amount: 0, source: 'manual')
    expect(sale).not_to be_valid
    expect(sale.errors[:amount]).to be_present
  end

  it 'aceita valor zero em venda automática e marca missing_amount' do
    sale = described_class.create!(amount: 0, source: 'pipeline')
    expect(sale.missing_amount).to be(true)
  end

  it 'preenche sold_at com o momento atual' do
    sale = described_class.create!(amount: 10)
    expect(sale.sold_at).to be_within(5.seconds).of(Time.current)
  end

  it 'conta venda às 22h30 de Brasília no dia local' do
    late = zone.local(2026, 11, 24, 22, 30)
    sale = create_sale(amount: 50, sold_at: late)
    expect(described_class.on_day(Date.new(2026, 11, 24))).to include(sale)
    expect(described_class.on_day(Date.new(2026, 11, 25))).not_to include(sale)
  end

  it 'agrupa por mês no fuso da instalação' do
    first_minute = zone.local(2026, 12, 1, 0, 10)
    last_minute = zone.local(2026, 11, 30, 23, 50) # 02:50 UTC de 01/12
    dec = create_sale(amount: 1, sold_at: first_minute)
    nov = create_sale(amount: 1, sold_at: last_minute)
    expect(described_class.in_month(Date.new(2026, 11, 1))).to include(nov)
    expect(described_class.in_month(Date.new(2026, 11, 1))).not_to include(dec)
  end

  it 'cancel! marca cancelada e sai do escopo active' do
    sale = create_sale(amount: 10)
    sale.cancel!
    expect(sale.reload.status).to eq('cancelled')
    expect(sale.cancelled_at).to be_present
    expect(described_class.active).not_to include(sale)
  end
end
