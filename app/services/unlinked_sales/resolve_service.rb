# frozen_string_literal: true

module UnlinkedSales
  # Resolves a sale from the review queue: ties it to a lead (manual link, kept by
  # later syncs) and replays the sync so the appointment and revenue land on it.
  class ResolveService
    def initialize(sale:, contact:, status:)
      @sale = sale
      @contact = contact
      @status = status
    end

    def perform
      result = nil
      ActiveRecord::Base.transaction do
        external_contact_id = @sale.payload.dig('contact', 'external_id').presence || "sale:#{@sale.external_id}"
        ExternalLink.find_or_initialize_by(source: @sale.source, external_type: 'contact', external_id: external_contact_id)
                    .update!(record: @contact)
        @sale.update!(status: @status, resolved_contact_id: @contact.id, resolved_at: Time.current)
        payload = @sale.payload.deep_dup
        payload['contact'] = (payload['contact'] || {}).merge('external_id' => external_contact_id)
        result = ExternalLeads::SyncService.new(payload).perform
        raise ActiveRecord::Rollback unless result[:success]
      end
      result || { success: false, errors: ['rolled back'] }
    end
  end
end
