# frozen_string_literal: true

# Token temporário (JWT HS256) que o CRM entrega ao n8n junto com cada mensagem. Só vale
# para a API /assistant/v1 desta instalação, por TTL minutos, para uma conversa e com o
# escopo do telefone. Revogar o telefone ou desligar o assistente invalida na hora.
module BusinessAssistant
  class Token
    TTL = 10.minutes
    ALGORITHM = 'HS256'

    Context = Struct.new(:phone, :name, :scope, :conversation_id, :jti, :expires_at, keyword_init: true)

    class Invalid < StandardError; end

    def self.issue(settings:, phone_entry:, conversation:, now: Time.current)
      jti = SecureRandom.uuid
      payload = {
        iss: settings.installation_id,
        aud: 'business_assistant',
        sub: phone_entry['phone'],
        scope: phone_entry['scope'],
        conv: conversation.id,
        jti: jti,
        iat: now.to_i,
        exp: (now + TTL).to_i
      }
      { token: JWT.encode(payload, key, ALGORITHM), jti: jti, expires_at: now + TTL }
    end

    def self.verify!(token, settings: Settings.load)
      raise Invalid, 'token ausente' if token.blank?

      payload, = JWT.decode(token, key, true,
                            algorithm: ALGORITHM, aud: 'business_assistant', verify_aud: true,
                            iss: settings.installation_id, verify_iss: true)
      raise Invalid, 'assistente desativado' unless settings.active?

      entry = settings.phone_entry_for(payload['sub'])
      raise Invalid, 'telefone não liberado' unless entry

      Context.new(phone: entry['phone'], name: entry['name'], scope: entry['scope'],
                  conversation_id: payload['conv'], jti: payload['jti'], expires_at: Time.zone.at(payload['exp']))
    rescue JWT::DecodeError => e
      raise Invalid, e.message
    end

    def self.key
      Rails.application.key_generator.generate_key('business_assistant/token', 64)
    end
  end
end
