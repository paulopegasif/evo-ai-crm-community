# frozen_string_literal: true

# Conversas/contatos criados para enviar o resumo diário ao dono não podem contaminar os
# indicadores (dashboard, tracking, Painel do Dia).
module DailySummary
  module Exclusion
    LABEL = 'resumo-diario'
    CONTACT_FLAG = 'internal_recipient'

    module_function

    def conversations(scope)
      scope.where('conversations.cached_label_list IS NULL OR conversations.cached_label_list NOT LIKE ?', "%#{LABEL}%")
    end

    def excluded_conversation_ids
      Conversation.where('conversations.cached_label_list LIKE ?', "%#{LABEL}%").select(:id)
    end

    def internal_contact_ids
      Contact.where("contacts.custom_attributes ->> ? = 'true'", CONTACT_FLAG).select(:id)
    end
  end
end
