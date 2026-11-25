# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DailyPanel::QuotePicker do
  let(:day) { Date.new(2026, 11, 25) }

  it 'tem frases em todas as categorias, com texto e autor/referência' do
    described_class::CATEGORIES.each do |category|
      list = described_class.quotes[category]
      expect(list.size).to be >= 20
      list.each do |item|
        expect(item['text']).to be_present
        expect(item['author'] || item['ref']).to be_present
      end
    end
  end

  it 'devolve a mesma frase no mesmo dia e frases diferentes em dias seguidos' do
    expect(described_class.pick('negocios', date: day)).to eq(described_class.pick('negocios', date: day))
    expect(described_class.pick('negocios', date: day)).not_to eq(described_class.pick('negocios', date: day + 1))
  end

  it 'mostra a referência para versículos' do
    expect(described_class.pick('biblia', date: day)[:author]).to match(/\d+:\d+/)
  end

  it 'devolve nil quando desligada' do
    expect(described_class.pick('off', date: day)).to be_nil
  end

  it 'usa a preferência do usuário ou o padrão da instalação' do
    allow(GlobalConfig).to receive(:get_value).with('DAILY_QUOTE_DEFAULT_CATEGORY').and_return('biblia')
    expect(described_class.category_for(User.new(ui_settings: {}))).to eq('biblia')
    expect(described_class.category_for(User.new(ui_settings: { 'daily_quote_category' => 'off' }))).to eq('off')
  end
end
