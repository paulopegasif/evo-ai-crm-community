# frozen_string_literal: true

# Configuração do resumo diário guardada em InstallationConfig DAILY_SUMMARY.
module DailySummary
  class Settings
    include ActiveModel::Model
    include ActiveModel::Attributes

    CONFIG_NAME = 'DAILY_SUMMARY'
    PHONE_FORMAT = /\A\+[1-9]\d{9,14}\z/
    TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
    WHATSAPP_CHANNELS = %w[Channel::Whatsapp Channel::WhatsappCloud].freeze
    MAX_PHONES = 5
    MAX_ATTEMPTS_PER_DAY = 3

    attribute :enabled, :boolean, default: false
    attribute :time, :string, default: '19:00'
    attribute :inbox_id, :string
    attribute :phones, default: -> { [] }
    attribute :last_run, default: -> {}

    validates :time, format: { with: TIME_FORMAT, message: 'deve estar no formato HH:MM' }
    validate :validate_phones
    validate :validate_inbox, if: :enabled

    def self.load
      raw = InstallationConfig.find_by(name: CONFIG_NAME)&.value
      raw = {} unless raw.is_a?(Hash)
      new(raw.with_indifferent_access.slice(*attribute_names))
    end

    def self.whatsapp_inboxes
      Inbox.where(channel_type: WHATSAPP_CHANNELS).order(:name)
    end

    def assign(params)
      self.enabled = params[:enabled] if params.key?(:enabled)
      self.time = params[:time].to_s.strip if params.key?(:time)
      self.inbox_id = params[:inbox_id].presence if params.key?(:inbox_id)
      self.phones = Array(params[:phones]).map { |p| normalize_phone(p) }.compact_blank.uniq if params.key?(:phones)
      self
    end

    def save
      return false unless valid?

      persist!
      true
    end

    def persist!
      config = InstallationConfig.find_or_initialize_by(name: CONFIG_NAME)
      config.value = attributes.except('last_run').merge('last_run' => last_run)
      config.locked = false if config.respond_to?(:locked=)
      config.save!
      GlobalConfig.clear_cache rescue nil # rubocop:disable Style/RescueModifier
    end

    def inbox
      inbox_id.present? ? self.class.whatsapp_inboxes.find_by(id: inbox_id) : nil
    end

    def zone
      Sales::TimeZone.current
    end

    def scheduled_at(date)
      hour, minute = time.split(':').map(&:to_i)
      zone.local(date.year, date.month, date.day, hour, minute)
    end

    def last_run_on?(date)
      last_run.is_a?(Hash) && last_run['date'] == date.iso8601
    end

    # Precisa enviar hoje? Já passou do horário, não concluiu e não esgotou as tentativas.
    def due?(now = zone.now)
      return false unless enabled && phones.any? && inbox
      return false if now < scheduled_at(now.to_date)
      return true unless last_run_on?(now.to_date)

      last_run['status'] != 'sent' && last_run['attempts'].to_i < MAX_ATTEMPTS_PER_DAY
    end

    def record_run!(date:, status:, errors:)
      attempts = last_run_on?(date) ? last_run['attempts'].to_i + 1 : 1
      self.last_run = {
        'date' => date.iso8601, 'status' => status, 'attempts' => attempts,
        'error' => errors.presence&.map { |e| "#{e[:phone]}: #{e[:error]}" }&.join('; '),
        'sent_at' => Time.current.iso8601
      }
      persist!
    end

    def as_json(*)
      {
        enabled: enabled,
        time: time,
        inbox_id: inbox_id,
        phones: phones,
        last_run: last_run&.slice('date', 'status', 'error', 'sent_at'),
        available_inboxes: self.class.whatsapp_inboxes.map do |i|
          { id: i.id, name: i.name, phone_number: i.channel.try(:phone_number) }
        end,
        timezone: zone.tzinfo.name
      }
    end

    private

    def normalize_phone(value)
      digits = value.to_s.gsub(/[^\d+]/, '')
      return nil if digits.blank?

      digits.start_with?('+') ? digits : "+#{digits}"
    end

    def validate_phones
      invalid = phones.reject { |p| p.match?(PHONE_FORMAT) }
      errors.add(:phones, "inválidos: #{invalid.join(', ')}") if invalid.any?
      errors.add(:phones, "máximo de #{MAX_PHONES} números") if phones.size > MAX_PHONES
      errors.add(:phones, 'informe ao menos um número') if enabled && phones.empty?
    end

    def validate_inbox
      if self.class.whatsapp_inboxes.none?
        errors.add(:inbox_id, 'conecte um WhatsApp para ativar o resumo')
      elsif inbox.nil?
        errors.add(:inbox_id, 'escolha a caixa de WhatsApp usada para enviar')
      end
    end
  end
end
