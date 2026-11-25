# frozen_string_literal: true

# Contador mensal de mensagens encaminhadas ao agente (mês no fuso da instalação) e controle
# do aviso "limite atingido" (no máximo um por telefone por dia).
module BusinessAssistant
  module Usage
    module_function

    def current_count(now = Sales::TimeZone.current.now)
      Redis::Alfred.get(month_key(now)).to_i
    end

    def exceeded?(limit, now = Sales::TimeZone.current.now)
      current_count(now) >= limit.to_i
    end

    def increment!(now = Sales::TimeZone.current.now)
      key = month_key(now)
      count = Redis::Alfred.incr(key)
      Redis::Alfred.expire(key, 40.days.to_i) if count == 1
      count
    end

    # true só na primeira vez no dia para o telefone.
    def claim_limit_notice!(phone, now = Sales::TimeZone.current.now)
      key = "business_assistant:limit_notice:#{now.to_date.iso8601}:#{phone}"
      Redis::Alfred.set(key, '1', nx: true, ex: 36.hours.to_i)
    end

    def month_key(now)
      "business_assistant:usage:#{now.strftime('%Y-%m')}"
    end
  end
end
