# frozen_string_literal: true

# Resposta do agente ao dono, enviada pela caixa do assistente na conversa do token.
class Assistant::V1::RepliesController < Assistant::V1::BaseController
  MAX_LENGTH = 4096

  def create
    conversation = token_conversation
    return error_response(ApiErrorCodes::FORBIDDEN, 'Conversa fora do escopo do token', status: :forbidden) unless conversation

    content = params[:content].to_s.strip
    if content.empty? || content.length > MAX_LENGTH
      return error_response(ApiErrorCodes::VALIDATION_ERROR, "content deve ter entre 1 e #{MAX_LENGTH} caracteres",
                            status: :unprocessable_entity)
    end

    BusinessAssistant::PendingReply.close!(assistant_context.jti)
    message = BusinessAssistant::Notifier.send_text(conversation, content)
    success_response(data: { message_id: message.id, conversation_id: conversation.id }, status: :created)
  end
end
