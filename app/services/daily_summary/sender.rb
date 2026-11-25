# frozen_string_literal: true

# Envia o resumo para cada número configurado. Fora do modo teste, cada número recebe no
# máximo uma mensagem por dia (chave Redis gravada só após envio bem-sucedido).
module DailySummary
  class Sender
    REDIS_TTL = 36.hours

    def initialize(settings: Settings.load, date: Sales::TimeZone.today, test: false)
      @settings = settings
      @date = date
      @test = test
    end

    def call
      inbox = @settings.inbox
      raise ArgumentError, 'Nenhuma caixa de WhatsApp configurada' unless inbox

      content = MessageBuilder.new(date: @date, test: @test).call
      sent = 0
      failed = []
      @settings.phones.each do |phone|
        next if !@test && already_sent?(phone)

        deliver(inbox, phone, content)
        mark_sent(phone) unless @test
        sent += 1
      rescue StandardError => e
        Rails.logger.error("[DailySummary] Falha ao enviar para #{phone}: #{e.message}")
        failed << { phone: phone, error: e.message }
      end

      record(sent, failed) unless @test
      { sent: sent, failed: failed }
    end

    private

    def deliver(inbox, phone, content)
      digits = whatsapp_digits(phone)
      contact = recipient_contact(inbox, digits)
      result = Messaging::OutboundToContactService.new(
        inbox: inbox, contact: contact, source_id: digits, content: content
      ).call
      raise result.error unless result.success?

      conversation = result.conversation
      conversation.add_labels([Exclusion::LABEL])
      conversation.update!(status: :resolved)
    end

    # Mesmo formato que o CRM usa para contatos de WhatsApp (porta do createJid do Evolution).
    def whatsapp_digits(phone)
      Whatsapp::PhoneNumberNormalizer.call(phone).presence || phone.delete('+')
    end

    def recipient_contact(inbox, digits)
      existing = ContactInbox.find_by(inbox_id: inbox.id, source_id: digits)&.contact
      contact = existing || Contact.find_by(phone_number: "+#{digits}") ||
                Contact.create!(name: "Resumo diário (+#{digits})", phone_number: "+#{digits}")
      attrs = (contact.custom_attributes || {}).merge(Exclusion::CONTACT_FLAG => true)
      contact.update!(custom_attributes: attrs) unless contact.custom_attributes&.dig(Exclusion::CONTACT_FLAG) == true
      contact
    end

    def redis_key(phone)
      "daily_summary:#{@date.iso8601}:#{phone}"
    end

    def already_sent?(phone)
      Redis::Alfred.exists?(redis_key(phone))
    end

    def mark_sent(phone)
      Redis::Alfred.set(redis_key(phone), '1', ex: REDIS_TTL.to_i)
    end

    def record(sent, failed)
      status = if failed.empty? then 'sent'
               elsif sent.zero? then 'failed'
               else
                 'partial'
               end
      @settings.record_run!(date: @date, status: status, errors: failed)
    end
  end
end
