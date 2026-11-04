# frozen_string_literal: true

require 'csv'

module Dashboard
  # One row per lead of the Lead Tracking cohort (same period and filters), with
  # origin, estimated cost, current stage, first evaluation and revenue.
  class LeadListService
    SORTS = %w[entered_at estimated_cost revenue].freeze
    PER_PAGE = 50
    MAX_PER_PAGE = 200
    CSV_HEADERS = {
      name: 'Nome', phone_number: 'Telefone', entered_at: 'Entrada', source: 'Origem', campaign_name: 'Campanha',
      adset_name: 'Conjunto', ad_name: 'Anúncio', estimated_cost: 'Custo estimado', cost_basis: 'Base do custo',
      stage_name: 'Etapa', evaluation_at: 'Avaliação', evaluation_status: 'Status da avaliação', revenue: 'Receita'
    }.freeze

    def initialize(params:)
      @params = params
    end

    def call
      rows = sorted(all_rows)
      page = [@params[:page].to_i, 1].max
      per_page = (@params[:per_page].presence || PER_PAGE).to_i.clamp(1, MAX_PER_PAGE)
      {
        leads: rows.slice((page - 1) * per_page, per_page) || [],
        meta: { page: page, per_page: per_page, total_count: rows.size, total_pages: (rows.size.to_f / per_page).ceil }
      }
    end

    def to_csv
      CSV.generate(col_sep: ';') do |csv|
        csv << CSV_HEADERS.values
        sorted(all_rows).each { |row| csv << CSV_HEADERS.keys.map { |key| row[key] } }
      end
    end

    private

    def snapshot
      @snapshot ||= LeadTrackingService.new(params: @params).cohort_snapshot
    end

    def all_rows
      ids = snapshot[:ids]
      contacts = Contact.where(id: ids).to_a
      origins = LeadOrigin.batch(contacts, period: snapshot[:period])
      stages = current_stages(ids)
      evaluations = first_evaluations(ids)

      contacts.map do |contact|
        origin = origins[contact.id]
        evaluation = evaluations[contact.id]
        attribution = snapshot[:attribution][contact.id] || {}
        {
          id: contact.id, name: contact.name, phone_number: contact.phone_number,
          entered_at: contact.created_at.iso8601,
          source: attribution[:source] || origin[:source],
          campaign_name: attribution[:campaign_name] || origin[:campaign_name],
          adset_name: origin[:adset_name], ad_id: origin[:ad_id], ad_name: origin[:ad_name],
          estimated_cost: origin[:estimated_cost], cost_basis: origin[:cost_basis],
          stage_name: stages[contact.id],
          evaluation_at: evaluation&.first&.iso8601, evaluation_all_day: evaluation&.dig(2), evaluation_status: evaluation&.second,
          scheduled: snapshot[:scheduled].include?(contact.id), attended: snapshot[:attended].include?(contact.id),
          won: snapshot[:won].include?(contact.id), revenue: snapshot[:revenue][contact.id].to_f.round(2)
        }
      end
    end

    def sorted(rows)
      sort = SORTS.include?(@params[:sort].to_s) ? @params[:sort].to_s : 'entered_at'
      desc = @params[:order].to_s != 'asc'
      present, missing = rows.partition { |row| !row[sort.to_sym].nil? }
      present = present.sort_by { |row| row[sort.to_sym] }
      (desc ? present.reverse : present) + missing
    end

    # contact_id => stage name of the most recent card.
    def current_stages(ids)
      PipelineItem.joins(:pipeline_stage).where(contact_id: ids).order(updated_at: :asc)
                  .pluck(:contact_id, 'pipeline_stages.name').to_h
    end

    # contact_id => [start_time, status, all_day] of the first non-cancelled appointment.
    def first_evaluations(ids)
      Appointment.where(contact_id: ids).where.not(status: 'cancelled').order(start_time: :desc)
                 .pluck(:contact_id, :start_time, :status, :all_day)
                 .to_h { |id, start, status, all_day| [id, [start, status, all_day]] }
    end
  end
end
