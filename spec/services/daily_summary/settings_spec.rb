# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DailySummary::Settings do
  let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
  let(:inbox) { Inbox.create!(name: 'Atendimento', channel: Channel::Api.create!) }

  before do
    allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo')
    allow(described_class).to receive(:whatsapp_inboxes).and_return(Inbox.where(id: inbox.id))
  end

  def valid_settings(**overrides)
    described_class.new.assign({ enabled: true, time: '19:00', inbox_id: inbox.id, phones: ['+55 62 99999-0000'] }.merge(overrides))
  end

  it 'vem desativado por padrão' do
    expect(described_class.load.enabled).to be(false)
  end

  it 'normaliza e salva números válidos' do
    settings = valid_settings
    expect(settings.save).to be(true)
    expect(described_class.load.phones).to eq(['+5562999990000'])
  end

  it 'recusa número em formato inválido indicando qual' do
    settings = valid_settings(phones: ['123'])
    expect(settings.save).to be(false)
    expect(settings.errors[:phones].join).to include('+123')
  end

  it 'recusa mais de 5 números' do
    phones = (1..6).map { |i| "+556299999000#{i}" }
    expect(valid_settings(phones: phones).save).to be(false)
  end

  it 'não ativa sem caixa de WhatsApp conectada' do
    allow(described_class).to receive(:whatsapp_inboxes).and_return(Inbox.none)
    settings = valid_settings
    expect(settings.save).to be(false)
    expect(settings.errors[:inbox_id].join).to include('conecte um WhatsApp')
  end

  describe '#due?' do
    let(:settings) { valid_settings.tap(&:save) }

    it 'só depois do horário configurado' do
      expect(settings.due?(zone.local(2026, 11, 25, 18, 59))).to be(false)
      expect(settings.due?(zone.local(2026, 11, 25, 19, 0))).to be(true)
    end

    it 'não repete depois de enviado no dia' do
      settings.record_run!(date: Date.new(2026, 11, 25), status: 'sent', errors: [])
      expect(settings.due?(zone.local(2026, 11, 25, 20, 0))).to be(false)
      expect(settings.due?(zone.local(2026, 11, 26, 19, 5))).to be(true)
    end

    it 'tenta de novo após falha, até 3 vezes no dia' do
      3.times do |i|
        expect(settings.due?(zone.local(2026, 11, 25, 19, 5 + i))).to be(true)
        settings.record_run!(date: Date.new(2026, 11, 25), status: 'failed', errors: [{ phone: 'x', error: 'down' }])
      end
      expect(settings.due?(zone.local(2026, 11, 25, 20, 0))).to be(false)
      expect(described_class.load.last_run['error']).to include('down')
    end
  end
end
