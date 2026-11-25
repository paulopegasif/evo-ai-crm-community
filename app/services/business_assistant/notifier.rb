# frozen_string_literal: true

# Mensagens fixas que o próprio CRM envia ao dono, sem passar pela IA.
module BusinessAssistant
  module Notifier
    MESSAGES = {
      unavailable: 'O assistente está indisponível no momento. Tente novamente em alguns minutos.',
      limit_reached: 'O limite de mensagens do assistente neste mês foi atingido. Fale com o suporte para ampliar.',
      text_only: 'Por enquanto eu só entendo mensagens de texto. Pode escrever sua pergunta?'
    }.freeze

    module_function

    def deliver(conversation, kind)
      send_text(conversation, MESSAGES.fetch(kind), kind: kind)
    end

    def send_text(conversation, content, kind: 'agent', attachments: [])
      message = conversation.messages.new(
        content: content,
        message_type: :outgoing,
        inbox_id: conversation.inbox_id,
        content_attributes: { 'business_assistant' => kind.to_s }
      )
      attachments.each { |attrs| message.attachments.new(attrs) }
      message.save!
      message
    end
  end
end
