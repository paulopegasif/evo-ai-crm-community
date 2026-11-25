# frozen_string_literal: true

# Porta de entrada do assistente: só mensagens recebidas na caixa do assistente, com ele
# ativo, de um telefone liberado, viram job. O resto é ignorado sem chamar o n8n.
class BusinessAssistantListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message&.incoming?

    settings = BusinessAssistant::Settings.load
    return unless settings.enabled && settings.inbox_id.present?
    return unless message.inbox_id.to_s == settings.inbox_id.to_s
    return unless BusinessAssistant::Sender.phone_entry(settings, message.conversation)

    BusinessAssistant::DispatchJob.perform_later(message.id)
  end
end
