# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BusinessAssistant::Period do
  let(:today) { Date.new(2026, 11, 25) } # quarta-feira

  before { allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo') }

  def parse(params)
    described_class.parse(params, today: today)
  end

  it 'interpreta períodos nomeados' do
    expect(parse(period: 'today').as_json).to include(from: '2026-11-25', to: '2026-11-25')
    expect(parse(period: 'this_week').as_json).to include(from: '2026-11-23', to: '2026-11-25')
    expect(parse(period: 'last_week').as_json).to include(from: '2026-11-16', to: '2026-11-22')
    expect(parse(period: 'last_month').as_json).to include(from: '2026-10-01', to: '2026-10-31')
    expect(parse(period: 'last_7_days').as_json).to include(from: '2026-11-19', to: '2026-11-25', days: 7)
  end

  it 'interpreta últimos N dias e intervalo' do
    expect(parse(days: '10').as_json).to include(from: '2026-11-16', to: '2026-11-25', days: 10)
    expect(parse(from: '2026-11-01', to: '2026-11-15').as_json).to include(label: 'custom', days: 15)
  end

  it 'recusa entradas inválidas' do
    expect { parse(period: 'ontem') }.to raise_error(described_class::Invalid)
    expect { parse(days: '0') }.to raise_error(described_class::Invalid)
    expect { parse(days: 'dez') }.to raise_error(described_class::Invalid)
    expect { parse(from: '2026-11-20', to: '2026-11-01') }.to raise_error(described_class::Invalid)
    expect { parse(from: '25/11/2026') }.to raise_error(described_class::Invalid)
  end

  it 'usa o fuso da instalação nos limites do dia' do
    range = parse(period: 'today').range
    expect(range.first.utc.iso8601).to eq('2026-11-25T03:00:00Z')
    expect(range.last.utc.to_i).to eq(Time.utc(2026, 11, 26, 2, 59, 59).to_i)
  end

  it 'calcula o período anterior de mesma duração' do
    expect(parse(days: '7').previous.as_json).to include(from: '2026-11-12', to: '2026-11-18')
  end
end
