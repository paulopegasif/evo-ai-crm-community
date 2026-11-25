# frozen_string_literal: true

# Configuração do assistente de negócio no WhatsApp, guardada em InstallationConfig
# BUSINESS_ASSISTANT. Só o super admin altera (ver Api::V1::BusinessAssistantSettingsController).
# O segredo de assinatura fica criptografado e nunca sai pela API depois de gerado.
module BusinessAssistant
  class Settings
    include ActiveModel::Model
    include ActiveModel::Attributes

    CONFIG_NAME = 'BUSINESS_ASSISTANT'
    PHONE_FORMAT = /\A\+[1-9]\d{9,14}\z/
    SCOPES = %w[owner].freeze
    MAX_PHONES = 10
    DEFAULT_MONTHLY_LIMIT = 300
    MIN_SECRET_LENGTH = 32

    attribute :enabled, :boolean, default: false
    attribute :installation_id, :string
    attribute :inbox_id, :string
    attribute :webhook_url, :string
    attribute :signing_secret_ciphertext, :string
    attribute :monthly_limit, :integer, default: DEFAULT_MONTHLY_LIMIT
    attribute :phones, default: -> { [] }

    # Preenchido só na requisição em que um segredo novo é gerado, para o super admin
    # copiar para o n8n. Não é persistido em texto puro.
    attr_reader :generated_secret

    validates :monthly_limit, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100_000 }
    validate :validate_phones
    validate :validate_webhook_url
    validate :validate_inbox, if: -> { enabled || inbox_id.present? }
    validate :validate_ready_to_enable, if: :enabled

    def self.load
      raw = InstallationConfig.find_by(name: CONFIG_NAME)&.value
      raw = {} unless raw.is_a?(Hash)
      new(raw.with_indifferent_access.slice(*attribute_names))
    end

    def self.whatsapp_inboxes
      DailySummary::Settings.whatsapp_inboxes
    end

    def assign(params)
      params = params.with_indifferent_access
      self.enabled = params[:enabled] if params.key?(:enabled)
      self.inbox_id = params[:inbox_id].presence if params.key?(:inbox_id)
      self.webhook_url = params[:webhook_url].to_s.strip.presence if params.key?(:webhook_url)
      self.monthly_limit = params[:monthly_limit] if params.key?(:monthly_limit)
      assign_phones(params)
      assign_secret(params)
      self
    end

    def save
      return false unless valid?

      self.installation_id ||= SecureRandom.uuid
      config = InstallationConfig.find_or_initialize_by(name: CONFIG_NAME)
      config.value = attributes
      config.locked = false if config.respond_to?(:locked=)
      config.save!
      GlobalConfig.clear_cache rescue nil # rubocop:disable Style/RescueModifier
      true
    end

    def inbox
      inbox_id.present? ? self.class.whatsapp_inboxes.find_by(id: inbox_id) : nil
    end

    def signing_secret
      return if signing_secret_ciphertext.blank?

      self.class.encryptor.decrypt_and_verify(signing_secret_ciphertext)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def secret_set?
      signing_secret.present?
    end

    # Telefone liberado que corresponde ao número informado (qualquer formato), ou nil.
    def phone_entry_for(raw_number)
      digits = self.class.whatsapp_digits(raw_number)
      return if digits.blank?

      phones.find { |entry| self.class.whatsapp_digits(entry['phone']) == digits }
    end

    def active?
      enabled && inbox.present? && webhook_url.present? && secret_set?
    end

    def as_json(*)
      {
        enabled: enabled,
        installation_id: installation_id,
        inbox_id: inbox_id,
        webhook_url: webhook_url,
        secret_set: secret_set?,
        monthly_limit: monthly_limit,
        phones: phones,
        usage_this_month: BusinessAssistant::Usage.current_count,
        available_inboxes: self.class.whatsapp_inboxes.map do |i|
          { id: i.id, name: i.name, phone_number: i.channel.try(:phone_number) }
        end
      }.tap { |json| json[:generated_secret] = generated_secret if generated_secret }
    end

    # Mesma forma canônica que o CRM usa para contatos de WhatsApp (só dígitos).
    def self.whatsapp_digits(raw)
      cleaned = raw.to_s.split('@').first.to_s.gsub(/\D/, '')
      return if cleaned.blank?

      Whatsapp::PhoneNumberNormalizer.call(cleaned).presence || cleaned
    end

    def self.encryptor
      key = Rails.application.key_generator.generate_key('business_assistant/signing_secret', 32)
      ActiveSupport::MessageEncryptor.new(key)
    end

    private

    def assign_secret(params)
      if ActiveModel::Type::Boolean.new.cast(params[:regenerate_secret])
        @generated_secret = SecureRandom.hex(32)
        self.signing_secret_ciphertext = self.class.encryptor.encrypt_and_sign(@generated_secret)
      elsif params[:signing_secret].present?
        secret = params[:signing_secret].to_s.strip
        if secret.length < MIN_SECRET_LENGTH
          @invalid_secret = true
        else
          self.signing_secret_ciphertext = self.class.encryptor.encrypt_and_sign(secret)
        end
      end
    end

    def assign_phones(params)
      self.phones = Array(params[:phones]).filter_map { |p| normalize_phone_entry(p) } if params.key?(:phones)
    end

    def normalize_phone_entry(entry)
      entry = entry.to_h.with_indifferent_access if entry.respond_to?(:to_h)
      return unless entry.is_a?(Hash)

      raw = entry[:phone].to_s.gsub(/[^\d+]/, '')
      return if raw.blank?

      {
        'phone' => raw.start_with?('+') ? raw : "+#{raw}",
        'name' => entry[:name].to_s.strip,
        'scope' => entry[:scope].presence || 'owner'
      }
    end

    def validate_phones
      add_phone_error('inválidos', phones.reject { |p| p['phone'].to_s.match?(PHONE_FORMAT) })
      add_phone_error('repetidos', repeated_phones)
      validate_phone_details
      errors.add(:phones, "máximo de #{MAX_PHONES} telefones") if phones.size > MAX_PHONES
    end

    def validate_phone_details
      errors.add(:phones, 'informe o nome de cada telefone') if phones.any? { |p| p['name'].blank? }
      errors.add(:phones, "escopo inválido (use: #{SCOPES.join(', ')})") if phones.any? { |p| SCOPES.exclude?(p['scope']) }
    end

    def add_phone_error(label, entries)
      errors.add(:phones, "#{label}: #{entries.pluck('phone').uniq.join(', ')}") if entries.any?
    end

    def repeated_phones
      digits = phones.map { |p| self.class.whatsapp_digits(p['phone']) }
      phones.select.with_index { |_, i| digits.count(digits[i]) > 1 }
    end

    def validate_webhook_url
      return if webhook_url.blank?

      uri = URI.parse(webhook_url)
      errors.add(:webhook_url, 'deve ser uma URL http(s) válida') unless uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      errors.add(:webhook_url, 'deve ser uma URL http(s) válida')
    end

    def validate_inbox
      selected = inbox
      if selected.nil?
        errors.add(:inbox_id, 'escolha a caixa de WhatsApp dedicada ao assistente')
      elsif selected.agent_bot_inbox.present?
        errors.add(:inbox_id, 'a caixa do assistente precisa ser dedicada (há um agente bot conectado nela)')
      elsif DailySummary::Settings.load.inbox_id.to_s == selected.id.to_s
        errors.add(:inbox_id, 'a caixa do assistente precisa ser dedicada (ela é usada pelo resumo diário)')
      end
    end

    def validate_ready_to_enable
      errors.add(:signing_secret, "deve ter ao menos #{MIN_SECRET_LENGTH} caracteres") if @invalid_secret
      errors.add(:webhook_url, 'informe a URL do webhook do n8n') if webhook_url.blank?
      errors.add(:signing_secret, 'gere o segredo de assinatura') unless secret_set?
      errors.add(:phones, 'libere ao menos um telefone') if phones.empty?
    end
  end
end
