# frozen_string_literal: true

module Dashboard
  # Everything known about one lead, in chronological order: entry and origin,
  # conversations (live and mirrored), stage changes, appointments and sales.
  class LeadJourneyService
    MAX_MESSAGES_PER_CONVERSATION = 500

    def initialize(contact:)
      @contact = contact
    end

    def call
      origin = LeadOrigin.for(@contact)
      revenue = appointments.select { |a| a.status == 'attended' }.sum { |a| a.price.to_f }.round(2)
      {
        contact: { id: @contact.id, name: @contact.name, phone_number: @contact.phone_number, email: @contact.email,
                   created_at: @contact.created_at.iso8601,
                   customer_type: @contact.custom_attributes&.dig('customer_type') },
        origin: origin,
        summary: {
          estimated_cost: origin[:estimated_cost], revenue: revenue,
          roi: origin[:estimated_cost].to_f.positive? ? (revenue / origin[:estimated_cost]).round(1) : nil,
          sale_match: sale_match
        },
        conversations: conversations,
        events: events.sort_by { |e| e[:at].to_s }
      }
    end

    private

    def appointments
      @appointments ||= Appointment.where(contact: @contact).includes(:user).order(:start_time).to_a
    end

    def pipeline_items
      @pipeline_items ||= PipelineItem.where(contact: @contact).includes(:pipeline, :pipeline_stage).to_a
    end

    # How the external sale was tied to this lead ("name" can be undone in the review queue).
    def sale_match
      link = ExternalLink.where(external_type: 'contact', record: @contact).order(:created_at).last
      return nil unless link

      manual = UnlinkedSale.exists?(resolved_contact_id: @contact.id, status: 'linked')
      { source: link.source, external_contact_id: link.external_id, match: manual ? 'manual' : 'automatic' }
    end

    def events
      [{ type: 'lead_created', at: @contact.created_at.iso8601 }] + stage_events + appointment_events
    end

    def stage_events
      StageMovement.where(pipeline_item_id: pipeline_items.map(&:id)).includes(:from_stage, :to_stage).map do |m|
        { type: 'stage_changed', at: m.created_at.iso8601, from: m.from_stage&.name, to: m.to_stage&.name,
          movement_type: m.movement_type }
      end
    end

    def appointment_events
      appointments.flat_map do |a|
        event = { type: 'appointment', at: a.start_time.iso8601, id: a.id, all_day: a.all_day, status: a.status,
                  category: a.category, price: a.price.to_f, user_name: a.user&.name,
                  source: a.custom_attributes&.dig('source') }
        sale = a.status == 'attended' && a.price.to_f.positive? ? [event.merge(type: 'sale')] : []
        [event] + sale
      end
    end

    def conversations
      Conversation.where(contact: @contact).includes(:inbox).order(:created_at).map do |conversation|
        messages = conversation.messages.reorder(:created_at).limit(MAX_MESSAGES_PER_CONVERSATION)
                               .pluck(:id, :message_type, :private, :content, :created_at, :content_attributes)
        {
          id: conversation.id, inbox_name: conversation.inbox&.name,
          mirrored: conversation.inbox&.channel.respond_to?(:read_only_mirror?) && conversation.inbox.channel.read_only_mirror?,
          started_at: conversation.created_at.iso8601,
          messages: messages.map do |id, type, priv, content, at, attrs|
            { id: id, message_type: type, private: priv, content: content, created_at: at.iso8601,
              author_name: attrs.is_a?(Hash) ? attrs['author_name'] : nil }
          end
        }
      end
    end
  end
end
