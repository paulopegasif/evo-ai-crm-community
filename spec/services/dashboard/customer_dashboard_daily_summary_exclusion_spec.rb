# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe Dashboard::CustomerDashboardService, 'exclusão do resumo diário' do
  include SalesFixtures

  let(:inbox) { Inbox.create!(name: 'Atendimento', channel: Channel::Api.create!) }

  it 'não conta conversas e mensagens do resumo diário' do
    real = create_conversation(contact: create_contact('Lead'), inbox: inbox)
    real.messages.create!(content: 'Oi', message_type: :incoming, inbox: inbox)

    summary = create_conversation(contact: create_contact('Dono'), inbox: inbox)
    summary.messages.create!(content: 'Resumo', message_type: :outgoing, inbox: inbox)
    summary.add_labels([DailySummary::Exclusion::LABEL])

    stats = described_class.new(params: {}).call[:stats]
    expect(stats[:total_conversations]).to eq(1)
    expect(stats[:outgoing_messages_count]).to eq(0)
    expect(stats[:incoming_messages_count]).to eq(1)
  end
end
