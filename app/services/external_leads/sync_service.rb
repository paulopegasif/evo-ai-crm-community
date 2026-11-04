# frozen_string_literal: true

module ExternalLeads
  # rubocop:disable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength
  class SyncService
    E164_FORMAT = /\A\+[1-9]\d{1,14}\z/
    FUTURE_TOLERANCE = 5.minutes
    DEAL_KINDS = %w[lead sale repurchase].freeze
    # Status precedence: a status set in the CRM is never moved backwards by the sync.
    STATUS_RANK = { 'cancelled' => 0, 'rescheduled' => 1, 'scheduled' => 1, 'confirmed' => 2, 'no_show' => 3, 'attended' => 4 }.freeze
    ACCENTS_FROM = 'áàâãäéèêëíìîïóòôõöúùûüçñ'
    ACCENTS_TO = 'aaaaaeeeeiiiiooooouuuucn'

    def initialize(params = {})
      @raw_params = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
      @params = @raw_params.deep_symbolize_keys

      @source = @params[:source].to_s.strip
      @external_id = @params[:external_id].to_s.strip
      @contact_params = (@params[:contact] || {}).deep_symbolize_keys
      @referral_params = (@params[:referral] || {}).deep_symbolize_keys
      @deal_params = (@params[:deal] || {}).deep_symbolize_keys
      @appointments_params = Array(@params[:appointments]).map(&:deep_symbolize_keys)
      @fallback_params = (@params[:referral_fallback] || {}).deep_symbolize_keys
      @deal_kind = @deal_params[:kind].presence || 'lead'

      @errors = []
    end

    def perform
      validate!
      return failure_response if @errors.any?

      # No `return` inside the block: Rails 7.1 rolls back on a non-local return.
      ActiveRecord::Base.transaction do
        sync_contact!
        if @contact.nil?
          queue_unlinked_sale!
        else
          link_external_contact!
          record_attribution!
          sync_pipeline_item!
          sync_appointments!
          success_response
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      @errors << e.record.errors.full_messages.join(', ')
      failure_response
    rescue StandardError => e
      # Unexpected errors surface as 500 so the n8n flow retries the window
      # instead of filing the deal as a data problem (422).
      Rails.logger.error "ExternalLeads::SyncService error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      raise
    end

    private

    def validate!
      validate_top_level!
      validate_contact!
      validate_deal!
      validate_appointments!
    end

    def validate_top_level!
      @errors << 'source is required' if @source.blank?
      @errors << 'external_id is required' if @external_id.blank?
      @errors << "deal.kind is invalid: '#{@deal_kind}'" if DEAL_KINDS.exclude?(@deal_kind)
    end

    def sale?
      @deal_kind == 'sale'
    end

    def validate_contact!
      @errors << 'contact.name is required' if @contact_params[:name].blank?

      phone = @contact_params[:phone_number].to_s.strip
      if phone.blank?
        # Sales are often registered on a phone-less contact; they are tied to the lead by name.
        @errors << 'contact.phone_number is required' unless sale?
      elsif !E164_FORMAT.match?(phone)
        @errors << 'contact.phone_number must be in E.164 format'
      end

      return if @contact_params[:created_at].blank?

      parsed_time = parse_time(@contact_params[:created_at])
      if parsed_time.nil?
        @errors << 'contact.created_at is not a valid date'
      elsif parsed_time > (Time.current + FUTURE_TOLERANCE)
        @errors << 'contact.created_at cannot be in the future'
      end
    end

    def validate_deal!
      pipeline_id = @deal_params[:pipeline_id]
      stage_id = @deal_params[:stage_id]

      if pipeline_id.blank?
        @errors << 'deal.pipeline_id is required'
        return
      end

      if stage_id.blank?
        @errors << 'deal.stage_id is required'
        return
      end

      @pipeline = Pipeline.find_by(id: pipeline_id)
      unless @pipeline
        @errors << 'Pipeline not found'
        return
      end

      @stage = @pipeline.pipeline_stages.find_by(id: stage_id)
      return if @stage

      @errors << 'Stage not found or does not belong to this pipeline'
    end

    def validate_appointments!
      @appointments_params.each_with_index do |apt, idx|
        prefix = "appointments[#{idx}]"
        @errors << "#{prefix}.external_id is required" if apt[:external_id].blank?

        if truthy?(apt[:all_day]) && apt[:date].present?
          @errors << "#{prefix}.date must be YYYY-MM-DD" unless apt[:date].to_s.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        elsif apt[:start_time].blank?
          @errors << "#{prefix}.start_time is required"
        elsif parse_time(apt[:start_time]).nil?
          @errors << "#{prefix}.start_time is not a valid date"
        end

        status = apt[:status].to_s.strip
        if status.blank?
          @errors << "#{prefix}.status is required"
        elsif Appointment::STATUSES.exclude?(status)
          @errors << "#{prefix}.status is invalid: '#{status}'"
        end

        # Validate professional user exists or can fallback
        user = resolve_user(apt[:professional_email])
        @errors << "#{prefix}.professional_email could not be resolved to a valid user" if user.nil?
      end
    end

    def sync_contact!
      phone = @contact_params[:phone_number].to_s.strip
      canonical_phone = Whatsapp::PhoneNumberNormalizer.to_e164(phone) || phone
      created_at_time = parse_time(@contact_params[:created_at])
      email = @contact_params[:email].to_s.strip.presence

      # 1. Lookup by external link (deal -> pipeline_item -> contact)
      deal_link = ExternalLink.find_by(source: @source, external_type: 'deal', external_id: @external_id)
      @contact = deal_link.record.contact if deal_link&.record.is_a?(PipelineItem)
      @match = 'deal' if @contact

      # 2. Lookup by the external contact id (same person in the source CRM)
      @contact ||= linked_external_contact
      @match ||= 'contact' if @contact

      # 3. Lookup by normalized or raw phone
      @contact ||= Contact.find_by(phone_number: canonical_phone) || Contact.find_by(phone_number: phone) if phone.present?
      @match ||= 'phone' if @contact

      # 4. Sales without a lead found so far: unique contact with the same normalized name.
      # A sale never creates a lead: without a match it goes to the review queue.
      if @contact.nil? && sale?
        @contact = match_contact_by_name
        @match = 'name' if @contact
        @contact_action = 'unchanged'
        return
      end

      if @contact.nil?
        attrs = {
          name: @contact_params[:name],
          phone_number: phone
        }
        # Only assign email if provided and not taken
        attrs[:email] = email if email && !Contact.exists?(email: email)

        @contact = Contact.new(attrs)
        @contact.created_at = created_at_time if created_at_time.present?
        # A repurchase never opens a new lead in the cohort.
        @contact.custom_attributes = (@contact.custom_attributes || {}).merge('customer_type' => 'returning') if @deal_kind == 'repurchase'
        @contact.save!
        @contact_action = 'created'
      else
        @contact_action = 'unchanged'
        @contact.with_lock do
          updated = false

          # Update name if changed
          if @contact_params[:name].present? && @contact.name != @contact_params[:name] && @match != 'name' && !sale?
            @contact.name = @contact_params[:name]
            updated = true
          end

          # Update email if missing and not taken
          if email && @contact.email.blank? && !Contact.where.not(id: @contact.id).exists?(email: email)
            @contact.email = email
            updated = true
          end

          if updated
            @contact.save!
            @contact_action = 'updated'
          end

          # created_at: only backfill backwards (a sale never moves the lead's entry date)
          if !sale? && created_at_time.present? && created_at_time < @contact.created_at
            @contact.update_columns(created_at: created_at_time) # rubocop:disable Rails/SkipsModelValidations
            @contact_action = 'updated'
          end
        end
      end
    end

    def linked_external_contact
      external_contact_id = @contact_params[:external_id].to_s.strip
      return nil if external_contact_id.blank?

      link = ExternalLink.find_by(source: @source, external_type: 'contact', external_id: external_contact_id)
      link&.record if link&.record.is_a?(Contact)
    end

    def link_external_contact!
      external_contact_id = @contact_params[:external_id].to_s.strip
      return if external_contact_id.blank?

      link = ExternalLink.find_or_initialize_by(source: @source, external_type: 'contact', external_id: external_contact_id)
      # A manual link from the review queue always wins over automatic matching.
      return if link.persisted? && link.record_id != @contact.id && manual_link?(link)

      link.record = @contact
      link.save!
    end

    def manual_link?(link)
      UnlinkedSale.exists?(source: @source, resolved_contact_id: link.record_id, status: 'linked')
    end

    def normalized_name(value)
      value.to_s.downcase.tr(ACCENTS_FROM, ACCENTS_TO).gsub(/[^a-z ]/, ' ').squeeze(' ').strip
    end

    def name_candidates
      name = normalized_name(@contact_params[:name])
      return [] if name.split.size < 2

      sql = "regexp_replace(trim(translate(lower(contacts.name), '#{ACCENTS_FROM}', '#{ACCENTS_TO}')), '[^a-z ]+', ' ', 'g')"
      @name_candidates ||= Contact.where.not(phone_number: [nil, ''])
                                  .where("regexp_replace(#{sql}, ' +', ' ', 'g') = ?", name)
                                  .limit(5).to_a
    end

    def match_contact_by_name
      name_candidates.one? ? name_candidates.first : nil
    end

    # Sale with no lead to attach to: keep it for review, outside the lead cohort.
    def queue_unlinked_sale!
      sale = UnlinkedSale.find_or_initialize_by(source: @source, external_id: @external_id)
      return success_queued(sale) if sale.persisted? && sale.status != 'pending' # resolved in the review queue

      attended = @appointments_params.find { |apt| apt[:status].to_s == 'attended' } || @appointments_params.first || {}
      sale.assign_attributes(
        customer_name: @contact_params[:name],
        customer_phone: @contact_params[:phone_number].presence,
        reason: name_candidates.many? ? 'ambiguous_name' : 'no_match',
        candidate_contact_ids: name_candidates.map(&:id),
        amount: (attended[:price] || @deal_params[:value] || 0).to_f,
        category: attended[:category],
        sold_at: appointment_times(attended).first || parse_time(@contact_params[:created_at]),
        payload: @raw_params
      )
      sale.save!
      success_queued(sale)
    end

    def success_queued(sale)
      { success: true, queued: true, unlinked_sale: { id: sale.id, reason: sale.reason, status: sale.status } }
    end

    def record_attribution!
      return record_fallback_attribution! if @referral_params.blank?
      return record_fallback_attribution! if @referral_params[:source_id].blank? && @referral_params[:ctwa_clid].blank?

      Attribution::RecordService.new(
        contact: @contact,
        touch: @referral_params,
        source: :external_referral
      ).perform
    end

    # Origin inferred from the source CRM (deal title or source field) when there is
    # no ad referral. Replaced later if the real ad shows up.
    def record_fallback_attribution!
      return if sale? || @fallback_params[:source].blank?

      Attribution::RecordService.new(
        contact: @contact,
        touch: { utm_source: @fallback_params[:source], utm_medium: @fallback_params[:medium] }.compact,
        source: :external_fallback
      ).perform
    end

    def sync_pipeline_item!
      deal_value = @deal_params[:value].presence
      deal_link = ExternalLink.find_by(source: @source, external_type: 'deal', external_id: @external_id)

      @pipeline_item = deal_link.record if deal_link&.record.is_a?(PipelineItem)

      # Reuse active card in pipeline if no link exists
      @pipeline_item = @pipeline.pipeline_items.find_by(contact: @contact, conversation_id: nil, completed_at: nil) if @pipeline_item.nil?

      if @pipeline_item.nil?
        custom_fields = { 'lead_source' => @source }
        if deal_value.present?
          custom_fields['value'] = deal_value
          custom_fields['services'] = [{ 'name' => 'Procedimento', 'value' => deal_value.to_s }]
        end

        @pipeline_item = @pipeline.pipeline_items.create!(
          contact: @contact,
          pipeline_stage: @stage,
          entered_at: Time.current,
          completed_at: (@stage.stage_type == 'completed' ? Time.current : nil),
          custom_fields: custom_fields
        )

        ExternalLink.create!(
          source: @source,
          external_type: 'deal',
          external_id: @external_id,
          record: @pipeline_item
        )
        @pipeline_item_action = 'created'
      else
        @pipeline_item_action = 'unchanged'
        changes = false

        if @pipeline_item.pipeline_stage_id != @stage.id
          @pipeline_item.pipeline_stage = @stage
          @pipeline_item.entered_at = Time.current
          changes = true
        end

        if @stage.stage_type == 'completed' && @pipeline_item.completed_at.nil?
          @pipeline_item.completed_at = Time.current
          changes = true
        end

        if deal_value.present?
          cf = (@pipeline_item.custom_fields || {}).deep_dup
          if cf['value'] != deal_value || cf['services'].blank?
            cf['value'] = deal_value
            cf['services'] = [{ 'name' => 'Procedimento', 'value' => deal_value.to_s }] if cf['services'].blank?
            @pipeline_item.custom_fields = cf
            changes = true
          end
        end

        if changes
          @pipeline_item.save!
          @pipeline_item_action = 'updated'
        end

        # Ensure link exists
        ExternalLink.find_or_create_by!(source: @source, external_type: 'deal', external_id: @external_id) do |l|
          l.record = @pipeline_item
        end
      end
    end

    def sync_appointments!
      @appointments_results = []

      @appointments_params.each do |apt|
        apt_external_id = apt[:external_id].to_s.strip
        apt_link = ExternalLink.find_by(source: @source, external_type: 'appointment', external_id: apt_external_id)
        appointment = apt_link&.record if apt_link&.record.is_a?(Appointment)

        all_day = truthy?(apt[:all_day])
        start_time, end_time = appointment_times(apt)
        duration = all_day ? 24 * 60 : (apt[:duration_minutes] || 60).to_i
        duration = 60 if duration <= 0
        end_time ||= start_time + duration.minutes
        price = (apt[:price] || 0.0).to_f
        title = apt[:title].presence || "Consulta - #{@contact.name}"
        category = apt[:category].presence || 'Geral'
        user = resolve_user(apt[:professional_email])

        if appointment.nil?
          appointment = Appointment.create!(
            user: user,
            contact: @contact,
            pipeline_item: @pipeline_item,
            title: title,
            category: category,
            start_time: start_time,
            end_time: end_time,
            duration_minutes: duration,
            all_day: all_day,
            status: apt[:status],
            price: price,
            custom_attributes: { 'source' => @source, 'external_id' => apt_external_id }
          )

          ExternalLink.create!(
            source: @source,
            external_type: 'appointment',
            external_id: apt_external_id,
            record: appointment
          )

          @appointments_results << { id: appointment.id, external_id: apt_external_id, action: 'created' }
        else
          action = 'unchanged'
          changes = false

          status = resolved_status(appointment, apt[:status])
          if appointment.status != status
            appointment.status = status
            changes = true
          end

          if apt.key?(:price) && appointment.price != price
            appointment.price = price
            changes = true
          end

          if apt.key?(:category) && appointment.category != category
            appointment.category = category
            changes = true
          end

          if apt.key?(:title) && appointment.title != title
            appointment.title = title
            changes = true
          end

          if appointment.start_time != start_time || appointment.all_day != all_day
            appointment.all_day = all_day
            appointment.start_time = start_time
            appointment.end_time = end_time
            appointment.duration_minutes = duration
            changes = true
          end

          if appointment.user_id != user.id
            appointment.user = user
            changes = true
          end

          if appointment.contact_id != @contact.id
            appointment.contact = @contact
            changes = true
          end

          if appointment.pipeline_item_id != @pipeline_item.id
            appointment.pipeline_item = @pipeline_item
            changes = true
          end

          if changes
            appointment.save!
            action = 'updated'
          end

          @appointments_results << { id: appointment.id, external_id: apt_external_id, action: action }
        end
      end
    end

    # [start, end] of an appointment: a calendar day in the account zone for
    # all-day appointments, otherwise the given times.
    def appointment_times(apt)
      return [nil, nil] if apt.blank?
      return AccountTime.day_bounds(apt[:date]) if truthy?(apt[:all_day]) && apt[:date].present?

      start_time = parse_time(apt[:start_time])
      [start_time, apt[:end_time].present? ? parse_time(apt[:end_time]) : nil]
    end

    def resolved_status(appointment, incoming)
      override = appointment.custom_attributes&.dig('crm_override_status')
      return incoming if override.blank?
      return override if STATUS_RANK.fetch(override, 0) > STATUS_RANK.fetch(incoming.to_s, 0)

      incoming
    end

    def truthy?(value)
      ActiveModel::Type::Boolean.new.cast(value) == true
    end

    def resolve_user(email)
      if email.present?
        user = User.from_email(email)
        return user if user
      end

      default_email = ENV.fetch('EXTERNAL_LEADS_DEFAULT_USER_EMAIL', nil).presence
      if default_email.present?
        user = User.from_email(default_email)
        return user if user
      end

      User.first
    end

    def parse_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def success_response
      {
        success: true,
        contact: { id: @contact.id, action: @contact_action, match: @match },
        pipeline_item: { id: @pipeline_item.id, action: @pipeline_item_action },
        appointments: @appointments_results
      }
    end

    def failure_response
      {
        success: false,
        error: @errors.join(', '),
        errors: @errors
      }
    end
  end
  # rubocop:enable Metrics/ClassLength, Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/BlockLength
end
