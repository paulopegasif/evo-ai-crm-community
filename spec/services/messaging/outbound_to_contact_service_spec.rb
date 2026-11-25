# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/sales_fixtures')

RSpec.describe Messaging::OutboundToContactService do
  include SalesFixtures

  let(:inbox) { Inbox.create!(name: 'API', channel: Channel::Api.create!) }
  let(:contact) { create_contact('Dono') }

  def send_message(content = 'Oi')
    described_class.new(inbox: inbox, contact: contact, source_id: '5562999990000', content: content).call
  end

  it 'cria contact inbox, conversa e mensagem de saída' do
    result = send_message
    expect(result).to be_success
    expect(result.message).to be_outgoing
    expect(result.message.content).to eq('Oi')
    expect(result.conversation.contact).to eq(contact)
  end

  it 'reaproveita a mesma conversa nos envios seguintes' do
    first = send_message('1')
    second = send_message('2')
    expect(second.conversation.id).to eq(first.conversation.id)
    expect(ContactInbox.where(inbox: inbox, source_id: '5562999990000').count).to eq(1)
  end
end
