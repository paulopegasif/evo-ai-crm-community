# frozen_string_literal: true

# Envia uma mensagem de saída para um contato numa caixa (WhatsApp, SMS, Telegram...):
# encontra/cria o ContactInbox pelo source_id, encontra/cria a conversa e cria a mensagem
# `outgoing` — o envio real ao canal acontece pelos callbacks normais de Message.
# Extraído de ScheduledActions::ExecutorService para ser reaproveitado pelo resumo diário.
module Messaging
  class OutboundToContactService
    Result = Struct.new(:success, :error, :conversation, :message, keyword_init: true) do
      def success?
        success
      end
    end

    def initialize(inbox:, contact:, source_id:, content:, sender_id: nil)
      @inbox = inbox
      @contact = contact
      @source_id = source_id
      @content = content
      @sender_id = sender_id
    end

    def call
      contact_inbox = find_or_create_contact_inbox
      return contact_inbox if contact_inbox.is_a?(Result)

      conversation = find_or_create_conversation(contact_inbox)
      return conversation if conversation.is_a?(Result)

      message = conversation.messages.create!(
        content: @content,
        message_type: :outgoing,
        sender_id: @sender_id,
        inbox_id: @inbox.id,
        conversation_id: conversation.id
      )
      Result.new(success: true, conversation: conversation, message: message)
    end

    private

    def find_or_create_contact_inbox
      ContactInbox.find_by(inbox_id: @inbox.id, source_id: @source_id) ||
        ContactInbox.create!(inbox_id: @inbox.id, contact_id: @contact.id, source_id: @source_id)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, error: "Failed to create contact inbox: #{e.message}")
    end

    def find_or_create_conversation(contact_inbox)
      @inbox.conversations.find_by(contact_id: @contact.id) ||
        @inbox.conversations.create!(contact_id: @contact.id, contact_inbox_id: contact_inbox.id)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success: false, error: "Failed to create conversation: #{e.message}")
    end
  end
end
