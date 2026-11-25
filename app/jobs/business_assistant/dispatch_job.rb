# frozen_string_literal: true

# Encaminha uma mensagem liberada ao agente no n8n, com token temporário e assinatura.
# Se o n8n recusar, avisa o dono na hora; se aceitar, agenda o vigia de resposta.
module BusinessAssistant
  class DispatchJob < ApplicationJob
    queue_as :high

    REPLY_DEADLINE = 60.seconds

    def perform(message_id)
      message = Message.find_by(id: message_id)
      settings = Settings.load
      return unless eligible?(message, settings)

      conversation = message.conversation
      entry = Sender.phone_entry(settings, conversation)
      return unless entry

      DailySummary::Exclusion.mark_internal!(conversation, label: DailySummary::Exclusion::ASSISTANT_LABEL)

      return Notifier.deliver(conversation, :text_only) if message.content.to_s.strip.empty?
      return notify_limit(conversation, entry) if Usage.exceeded?(settings.monthly_limit)

      forward(settings, message, conversation, entry)
    end

    private

    def eligible?(message, settings)
      message&.incoming? && settings.active? && message.inbox_id.to_s == settings.inbox_id.to_s
    end

    def forward(settings, message, conversation, entry)
      issued = Token.issue(settings: settings, phone_entry: entry, conversation: conversation)
      result = WebhookClient.new(settings).post(payload(settings, message, conversation, entry, issued))

      unless result.success?
        Rails.logger.warn("[BusinessAssistant] n8n recusou a mensagem #{message.id}: #{result.error}")
        return Notifier.deliver(conversation, :unavailable)
      end

      Usage.increment!
      PendingReply.open!(issued[:jti])
      ReplyWatchdogJob.set(wait: REPLY_DEADLINE).perform_later(conversation.id, issued[:jti])
    end

    def notify_limit(conversation, entry)
      Notifier.deliver(conversation, :limit_reached) if Usage.claim_limit_notice!(entry['phone'])
    end

    def payload(settings, message, conversation, entry, issued)
      {
        event: 'message',
        installation_id: settings.installation_id,
        base_url: BusinessAssistant.base_url,
        conversation_id: conversation.id,
        message_id: message.id,
        phone: entry['phone'],
        name: entry['name'],
        scope: entry['scope'],
        text: message.content,
        timezone: Sales::TimeZone.current.tzinfo.name,
        token: issued[:token],
        token_expires_at: issued[:expires_at].iso8601,
        sent_at: message.created_at.iso8601
      }
    end
  end
end
