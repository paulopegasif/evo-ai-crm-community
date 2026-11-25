# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe DailySummary::Sender do
  include SalesFixtures

  let(:inbox) { Inbox.create!(name: 'Atendimento', channel: Channel::Api.create!) }
  let(:date) { Date.new(2026, 11, 25) }
  let(:key) { "daily_summary:#{date.iso8601}:+5562999990000" }
  let(:settings) do
    DailySummary::Settings.new.assign(enabled: true, time: '19:00', inbox_id: inbox.id, phones: ['+5562999990000'])
  end

  before do
    allow(Sales::TimeZone).to receive(:config_value).and_return('America/Sao_Paulo')
    allow(DailySummary::Settings).to receive(:whatsapp_inboxes).and_return(Inbox.where(id: inbox.id))
    settings.save
    Redis::Alfred.delete(key)
  end

  after { Redis::Alfred.delete(key) }

  it 'envia uma vez por número por dia, resolve a conversa e etiqueta' do
    expect(described_class.new(settings: settings, date: date).call).to eq(sent: 1, failed: [])
    expect(described_class.new(settings: DailySummary::Settings.load, date: date).call).to eq(sent: 0, failed: [])

    digits = Whatsapp::PhoneNumberNormalizer.call('+5562999990000')
    conversation = ContactInbox.find_by!(inbox: inbox, source_id: digits).conversations.first
    expect(conversation.messages.outgoing.count).to eq(1)
    expect(conversation).to be_resolved
    expect(conversation.label_list).to include('resumo-diario')
    expect(conversation.contact.custom_attributes['internal_recipient']).to be(true)
    expect(DailySummary::Settings.load.last_run).to include('status' => 'sent', 'date' => '2026-11-25')
  end

  it 'envio de teste não conta como envio do dia' do
    described_class.new(settings: settings, date: date, test: true).call
    expect(Redis::Alfred.exists?(key)).to be(false)
    expect(DailySummary::Settings.load.last_run).to be_nil
  end

  it 'registra falha quando o envio quebra' do
    allow(Messaging::OutboundToContactService).to receive(:new).and_raise(StandardError, 'WhatsApp desconectado')
    result = described_class.new(settings: settings, date: date).call
    expect(result[:failed].first[:error]).to eq('WhatsApp desconectado')
    expect(DailySummary::Settings.load.last_run).to include('status' => 'failed')
  end

  it 'o envio não aparece nos indicadores do painel' do
    described_class.new(settings: settings, date: date).call
    panel = DailyPanel::BuildService.new(user: nil, admin: true, today: date).call
    expect(panel[:todo][:awaiting_reply]).to eq(0)
  end
end
