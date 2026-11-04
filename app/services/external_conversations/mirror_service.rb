# frozen_string_literal: true

module ExternalConversations
  # Mirrors a conversation from an external CRM (Bitrix24 Open Channels) into a
  # read-only inbox. Everything is stored as `imported`, so no automation,
  # notification, AI agent or pipeline assignment runs and nothing is sent.
  # Idempotent by message id (`messages.source_id = "<source>:<id>"`).
  class MirrorService
    DIRECTIONS = %w[incoming outgoing system].freeze
    INBOX_NAME = 'WhatsApp (Bitrix24 · espelho)'

    def initialize(params)
      raw = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @params = raw.deep_symbolize_keys
      @source = @params[:source].to_s.strip
      @external_id = @params[:external_id].to_s.strip
      @contact_params = (@params[:contact] || {}).deep_symbolize_keys
      @messages = Array(@params[:messages]).map(&:deep_symbolize_keys)
      @errors = []
    end

    def self.mirror_inbox(source = 'bitrix24')
      Inbox.joins("INNER JOIN channel_api ON channel_api.id = inboxes.channel_id AND inboxes.channel_type = 'Channel::Api'")
           .find_by("channel_api.additional_attributes->>'read_only_mirror' = 'true' AND " \
                    "channel_api.additional_attributes->>'mirror_source' = ?", source) ||
        create_mirror_inbox(source)
    end

    def self.create_mirror_inbox(source)
      channel = Channel::Api.create!(additional_attributes: { 'read_only_mirror' => true, 'mirror_source' => source })
      Inbox.create!(name: INBOX_NAME, channel: channel)
    end

    def perform
      validate!
      return failure if @errors.any?

      @contact = resolve_contact
      return failure('contact not synced yet: send the lead first') if @contact.nil?

      created = 0
      ActiveRecord::Base.transaction do
        @inbox = self.class.mirror_inbox(@source)
        @conversation = find_or_create_conversation
        existing = Message.where(conversation: @conversation, source_id: source_ids).pluck(:source_id).to_set
        @messages.sort_by { |m| parse_time(m[:created_at]) }.each do |message|
          next if existing.include?(source_id_for(message))

          create_message(message)
          created += 1
        end
        touch_conversation
      end

      { success: true, conversation_id: @conversation.id, contact_id: @contact.id, created: created,
        skipped: @messages.size - created }
    end

    private

    def validate!
      @errors << 'source is required' if @source.blank?
      @errors << 'external_id is required' if @external_id.blank?
      if @contact_params[:deal_external_id].blank? && @contact_params[:external_id].blank? && @contact_params[:phone_number].blank?
        @errors << 'contact.deal_external_id, contact.external_id or contact.phone_number is required'
      end
      @messages.each_with_index do |m, i|
        @errors << "messages[#{i}].external_id is required" if m[:external_id].blank?
        @errors << "messages[#{i}].direction is invalid" if DIRECTIONS.exclude?(m[:direction].to_s)
        @errors << "messages[#{i}].created_at is not a valid date" if parse_time(m[:created_at]).nil?
      end
    end

    def resolve_contact
      by_link('deal', @contact_params[:deal_external_id]) { |record| record.try(:contact) } ||
        by_link('contact', @contact_params[:external_id]) { |record| record } ||
        by_phone
    end

    def by_link(type, external_id)
      return nil if external_id.blank?

      record = ExternalLink.find_by(source: @source, external_type: type, external_id: external_id.to_s)&.record
      record && yield(record)
    end

    def by_phone
      phone = @contact_params[:phone_number].to_s.strip
      return nil if phone.blank?

      canonical = Whatsapp::PhoneNumberNormalizer.to_e164(phone) || phone
      Contact.find_by(phone_number: canonical) || Contact.find_by(phone_number: phone)
    end

    def find_or_create_conversation
      link = ExternalLink.find_by(source: @source, external_type: 'conversation', external_id: @external_id)
      return link.record if link&.record.is_a?(Conversation)

      contact_inbox = ContactInbox.find_or_create_by!(inbox: @inbox, contact: @contact,
                                                      source_id: "#{@source}:#{@external_id}")
      started_at = @messages.filter_map { |m| parse_time(m[:created_at]) }.min || Time.current
      conversation = Conversation.new(
        inbox: @inbox, contact: @contact, contact_inbox: contact_inbox, status: :resolved, source: :imported,
        additional_attributes: { 'mirror_source' => @source, 'external_id' => @external_id }
      )
      conversation.created_at = started_at
      conversation.save!
      ExternalLink.create!(source: @source, external_type: 'conversation', external_id: @external_id, record: conversation)
      conversation
    end

    def source_ids
      @messages.map { |m| source_id_for(m) }
    end

    def source_id_for(message)
      "#{@source}:#{message[:external_id]}"
    end

    def create_message(message)
      direction = message[:direction].to_s
      attachments = Array(message[:attachments]).map { |a| a.slice(:url, :name) }
      content = [message[:content].to_s.presence, *attachments.map { |a| "📎 #{a[:name].presence || 'Anexo'}: #{a[:url]}" }]
                .compact.join("\n")
      msg = Message.new(
        inbox: @inbox, conversation: @conversation, source: :imported, source_id: source_id_for(message),
        message_type: { 'incoming' => :incoming, 'outgoing' => :outgoing, 'system' => :activity }[direction],
        private: direction == 'system',
        sender: direction == 'incoming' ? @contact : nil,
        content: content.presence || '(mensagem sem texto)',
        content_attributes: { 'author_name' => message[:author_name], 'mirrored' => true, 'attachments' => attachments }.compact
      )
      msg.created_at = parse_time(message[:created_at])
      msg.save!
    end

    def touch_conversation
      last = @conversation.messages.maximum(:created_at)
      @conversation.update_columns(last_activity_at: last) if last # rubocop:disable Rails/SkipsModelValidations
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError, TypeError
      nil
    end

    def failure(message = nil)
      @errors << message if message
      { success: false, error: @errors.join(', '), errors: @errors }
    end
  end
end
