# frozen_string_literal: true

require 'rails_helper'

# Concurrent creates must not collide on index_conversations_on_display_id.
# Needs real commits across threads, so transactional fixtures are off here and the
# records are removed by hand.
RSpec.describe Conversation, '#display_id', type: :model do
  self.use_transactional_tests = false

  let!(:channel) { Channel::Api.create! }
  let!(:inbox) { Inbox.create!(name: "display-id-#{SecureRandom.hex(3)}", channel: channel) }
  let!(:contacts) { Array.new(8) { |i| Contact.create!(name: "Display Id #{i}", email: "display-id-#{SecureRandom.hex(4)}@example.com") } }

  def create_conversation(contact)
    contact_inbox = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.hex(6))
    described_class.create!(inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  after do
    conversations = described_class.where(inbox_id: inbox.id)
    Message.where(conversation_id: conversations.select(:id)).delete_all
    PipelineItem.where(conversation_id: conversations.select(:id)).delete_all
    conversations.delete_all
    ContactInbox.where(inbox_id: inbox.id).delete_all
    Contact.where(id: contacts.map(&:id)).delete_all
    inbox.delete
    channel.delete
  end

  it 'assigns the next sequential display_id' do
    first = create_conversation(contacts[0])
    second = create_conversation(contacts[1])

    expect(second.display_id).to eq(first.display_id + 1)
  end

  it 'gives unique display_ids to conversations created concurrently' do
    gate = Queue.new
    errors = Queue.new

    threads = contacts.map do |contact|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          create_conversation(contact)
        rescue StandardError => e
          errors << e
        end
      end
    end
    contacts.size.times { gate << :go }
    threads.each(&:join)

    expect(errors.size).to eq(0), -> { "errors: #{Array.new(errors.size) { errors.pop.message }.uniq}" }
    display_ids = described_class.where(inbox_id: inbox.id).pluck(:display_id)
    expect(display_ids.size).to eq(contacts.size)
    expect(display_ids.uniq.size).to eq(contacts.size)
  end
end
