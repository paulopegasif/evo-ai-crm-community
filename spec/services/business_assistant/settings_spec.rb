# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/business_assistant_helpers')

RSpec.describe BusinessAssistant::Settings do
  include BusinessAssistantHelpers

  before { stub_whatsapp_inboxes }

  def build(**attrs)
    described_class.new.assign({
      enabled: true, inbox_id: assistant_inbox.id, webhook_url: BusinessAssistantHelpers::WEBHOOK_URL,
      signing_secret: BusinessAssistantHelpers::SECRET,
      phones: [{ phone: '+55 61 99999-0000', name: 'Carla', scope: 'owner' }]
    }.merge(attrs))
  end

  it 'aceita uma configuração completa, normaliza telefones e gera installation_id' do
    settings = build
    expect(settings.save).to be(true)
    loaded = described_class.load
    expect(loaded.phones).to eq([{ 'phone' => '+5561999990000', 'name' => 'Carla', 'scope' => 'owner' }])
    expect(loaded.installation_id).to be_present
    expect(loaded.signing_secret).to eq(BusinessAssistantHelpers::SECRET)
    expect(loaded).to be_active
  end

  it 'vem desligado por padrão' do
    expect(described_class.load.enabled).to be(false)
  end

  it 'exige caixa, webhook, segredo e telefone para ativar' do
    settings = described_class.new.assign(enabled: true)
    expect(settings).not_to be_valid
    expect(settings.errors.attribute_names).to include(:inbox_id, :webhook_url, :signing_secret, :phones)
  end

  it 'recusa telefone inválido, repetido, sem nome ou com escopo desconhecido' do
    settings = build(phones: [
                       { phone: '12', name: 'X' },
                       { phone: '+5561999990000', name: 'A' }, { phone: '5561999990000', name: 'B' },
                       { phone: '+5511988887777', name: '' },
                       { phone: '+5511977776666', name: 'Lucas', scope: 'seller' }
                     ])
    expect(settings).not_to be_valid
    messages = settings.errors[:phones].join(' | ')
    expect(messages).to include('inválidos: +12', 'repetidos', 'nome', 'escopo inválido')
  end

  it 'limita a 10 telefones' do
    phones = (0..10).map { |i| { phone: "+55619999900#{format('%02d', i)}", name: "P#{i}" } }
    expect(build(phones: phones).tap(&:valid?).errors[:phones].join).to include('máximo de 10')
  end

  it 'recusa caixa com agente bot conectado' do
    bot = AgentBot.create!(name: 'Bot')
    AgentBotInbox.create!(agent_bot: bot, inbox: assistant_inbox)
    expect(build.tap(&:valid?).errors[:inbox_id].join).to include('agente bot')
  end

  it 'recusa a caixa usada pelo resumo diário' do
    DailySummary::Settings.new.assign(inbox_id: assistant_inbox.id).save || raise('falhou')
    expect(build.tap(&:valid?).errors[:inbox_id].join).to include('resumo diário')
  end

  it 'recusa segredo curto e URL inválida' do
    settings = build(signing_secret: 'curto', webhook_url: 'ftp://x')
    settings.signing_secret_ciphertext = nil
    expect(settings).not_to be_valid
    expect(settings.errors.attribute_names).to include(:signing_secret, :webhook_url)
  end

  it 'gera segredo novo sob pedido e o expõe só nessa resposta' do
    settings = build(signing_secret: nil, regenerate_secret: true)
    expect(settings.save).to be(true)
    expect(settings.as_json[:generated_secret]).to match(/\A\h{64}\z/)
    expect(described_class.load.as_json).not_to have_key(:generated_secret)
    expect(described_class.load.as_json[:secret_set]).to be(true)
  end

  it 'encontra o telefone liberado em qualquer formato' do
    expect(build.save).to be(true)
    settings = described_class.load
    expect(settings.phone_entry_for('556199990000@s.whatsapp.net')['name']).to eq('Carla')
    expect(settings.phone_entry_for('+55 61 98888-7777')).to be_nil
  end
end
