# frozen_string_literal: true

# Se o agente não respondeu a tempo, avisa o dono uma única vez.
module BusinessAssistant
  class ReplyWatchdogJob < ApplicationJob
    queue_as :default

    def perform(conversation_id, jti)
      return unless PendingReply.close!(jti)

      conversation = Conversation.find_by(id: conversation_id)
      Notifier.deliver(conversation, :unavailable) if conversation
    end
  end
end
