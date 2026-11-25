# frozen_string_literal: true

# Identifica o telefone de quem escreveu na conversa do assistente.
module BusinessAssistant
  module Sender
    module_function

    def phone_entry(settings, conversation)
      return if conversation.nil?

      candidates = [conversation.contact_inbox&.source_id, conversation.contact&.phone_number].compact_blank
      candidates.lazy.map { |number| settings.phone_entry_for(number) }.find(&:itself)
    end
  end
end
