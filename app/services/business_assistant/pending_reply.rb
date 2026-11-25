# frozen_string_literal: true

# Marca de "aguardando resposta do agente" por token (jti). Quem fechar primeiro vence:
# a resposta do agente (fecha sem aviso) ou o vigia (fecha e avisa indisponibilidade).
module BusinessAssistant
  module PendingReply
    module_function

    def open!(jti)
      Redis::Alfred.set(key(jti), '1', ex: Token::TTL.to_i)
    end

    # true se estava pendente (e agora não está mais).
    def close!(jti)
      Redis::Alfred.delete(key(jti)).to_i.positive?
    end

    def key(jti)
      "business_assistant:pending:#{jti}"
    end
  end
end
