# frozen_string_literal: true

# Conversas/contatos internos (resumo diário ao dono e assistente de negócio no WhatsApp) não
# podem contaminar os indicadores (dashboard, tracking, Painel do Dia).
module DailySummary
  module Exclusion
    LABEL = 'resumo-diario'
    ASSISTANT_LABEL = 'assistente'
    LABELS = [LABEL, ASSISTANT_LABEL].freeze
    CONTACT_FLAG = 'internal_recipient'

    module_function

    def conversations(scope)
      LABELS.reduce(scope) do |rel, label|
        rel.where('conversations.cached_label_list IS NULL OR conversations.cached_label_list NOT LIKE ?', "%#{label}%")
      end
    end

    def excluded_conversation_ids
      conditions = LABELS.map { 'conversations.cached_label_list LIKE ?' }.join(' OR ')
      Conversation.where(conditions, *LABELS.map { |l| "%#{l}%" }).select(:id)
    end

    def internal_contact_ids
      Contact.where("contacts.custom_attributes ->> ? = 'true'", CONTACT_FLAG).select(:id)
    end

    # Marca contato e conversa como internos (fora das métricas).
    def mark_internal!(conversation, label:)
      conversation.add_labels([label]) unless conversation.label_list.include?(label)
      contact = conversation.contact
      return if contact.nil? || contact.custom_attributes&.dig(CONTACT_FLAG) == true

      contact.update!(custom_attributes: (contact.custom_attributes || {}).merge(CONTACT_FLAG => true))
    end
  end
end
