# frozen_string_literal: true

# POST assinado para o webhook do n8n. Assinatura: HMAC-SHA256(segredo, "<timestamp>.<corpo>")
# em X-Assistant-Signature (sha256=<hex>) + X-Assistant-Timestamp. O n8n confere a assinatura,
# a janela de tempo e a instalação antes de chamar a IA.
module BusinessAssistant
  class WebhookClient
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    Result = Struct.new(:success, :status, :error, :latency_ms, keyword_init: true) do
      def success?
        success
      end
    end

    def self.signature(secret, timestamp, body)
      "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")}"
    end

    def initialize(settings)
      @settings = settings
    end

    def post(payload)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = HTTParty.post(@settings.webhook_url, body: (body = payload.to_json), headers: headers_for(body),
                                                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      build_result(response, elapsed_ms(started))
    rescue StandardError => e
      Result.new(success: false, error: e.message.presence || e.class.name, latency_ms: elapsed_ms(started))
    end

    private

    def headers_for(body)
      timestamp = Time.current.to_i.to_s
      {
        'Content-Type' => 'application/json',
        'X-Assistant-Timestamp' => timestamp,
        'X-Assistant-Signature' => self.class.signature(@settings.signing_secret, timestamp, body),
        'X-Assistant-Installation' => @settings.installation_id.to_s
      }
    end

    def build_result(response, latency)
      return Result.new(success: true, status: response.code, latency_ms: latency) if response.code.between?(200, 299)

      Result.new(success: false, status: response.code, error: "HTTP #{response.code}", latency_ms: latency)
    end

    def elapsed_ms(started)
      return nil unless started

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end
  end
end
