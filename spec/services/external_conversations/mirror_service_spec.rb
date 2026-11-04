# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ExternalConversations::MirrorService do
  let!(:contact) { Contact.create!(name: 'Cássia Rodrigues', phone_number: '+5561985702132') }

  let(:payload) do
    {
      source: 'bitrix24',
      external_id: '73205',
      contact: { phone_number: '+5561985702132' },
      messages: [
        { external_id: '1', direction: 'system', content: 'Campanha Meta — ID da origem: 120260810960180456',
          created_at: '2026-10-01T10:00:00-03:00' },
        { external_id: '2', direction: 'incoming', content: 'Oi, vi o anúncio', created_at: '2026-10-01T10:01:00-03:00' },
        { external_id: '3', direction: 'outgoing', author_name: 'Maria Eduarda', content: 'Olá! Posso ajudar?',
          created_at: '2026-10-01T10:05:00-03:00', attachments: [{ url: 'https://bitrix/file/1', name: 'tabela.pdf' }] }
      ]
    }
  end

  it 'mirrors the conversation as imported messages with original times, author and direction' do
    result = described_class.new(payload).perform

    expect(result).to include(success: true, created: 3, skipped: 0)
    conversation = Conversation.find(result[:conversation_id])
    expect(conversation).to have_attributes(contact_id: contact.id, source: 'imported')
    expect(conversation.inbox.channel.read_only_mirror?).to be(true)
    expect(InboxSerializer.serialize(conversation.inbox)['read_only_mirror']).to be(true)

    messages = conversation.messages.reorder(:created_at).to_a
    expect(messages.map(&:message_type)).to eq(%w[activity incoming outgoing])
    expect(messages.first.private).to be(true)
    expect(messages.map(&:source)).to all(eq('imported'))
    expect(messages.second.created_at).to eq(Time.zone.parse('2026-10-01T10:01:00-03:00'))
    expect(messages.last.content_attributes['author_name']).to eq('Maria Eduarda')
    expect(messages.last.content).to include('tabela.pdf: https://bitrix/file/1')
  end

  it 'is idempotent and only adds new messages' do
    described_class.new(payload).perform
    payload[:messages] << { external_id: '4', direction: 'incoming', content: 'Quero agendar', created_at: '2026-10-02T09:00:00-03:00' }
    result = described_class.new(payload).perform

    expect(result).to include(created: 1, skipped: 3)
    expect(Message.count).to eq(4)
    expect(Conversation.count).to eq(1)
    expect(Inbox.count).to eq(1)
  end

  it 'does not enqueue notifications or automations' do
    expect { described_class.new(payload).perform }.not_to have_enqueued_job(SendReplyJob)
  end

  it 'finds the contact through the synced deal' do
    other = Contact.create!(name: 'Outra', phone_number: '+5561900000000')
    pipeline = Pipeline.create!(name: 'P', created_by: User.create!(email: 'x@example.com', name: 'X'))
    stage = PipelineStage.create!(pipeline: pipeline, name: 'S', position: 1)
    item = PipelineItem.create!(pipeline: pipeline, pipeline_stage: stage, contact: other)
    ExternalLink.create!(source: 'bitrix24', external_type: 'deal', external_id: 'deal_9', record: item)

    result = described_class.new(payload.merge(contact: { deal_external_id: 'deal_9' })).perform
    expect(result[:contact_id]).to eq(other.id)
  end

  it 'rejects a conversation whose lead is not synced yet' do
    result = described_class.new(payload.merge(contact: { phone_number: '+5511999999999' })).perform
    expect(result[:success]).to be(false)
    expect(Message.count).to eq(0)
  end
end
