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
    first = described_class.pick('negocios', date: day)
    expect(described_class.pick('negocios', date: day)).to eq(first)
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

  describe 'lista de frases' do
    let(:quotes) { YAML.safe_load_file(Rails.root.join('config/daily_quotes/pt_BR.yml')) }

    it 'tem frases suficientes em cada categoria, curtas e com autoria' do
      described_class::CATEGORIES.each do |category|
        items = quotes.fetch(category)
        expect(items.size).to be >= 60
        items.each do |item|
          expect(item['text'].length).to be <= 170
          expect(item['author'].presence || item['ref'].presence).to be_present
        end
      end
    end

    it 'credita a Bíblia Livre em todo versículo (CC BY 4.0)' do
      quotes.fetch('biblia').each do |item|
        expect(item['ref']).to end_with('(BLIVRE)')
        expect(item['text']).not_to include('[')
      end
    end
  end
end
