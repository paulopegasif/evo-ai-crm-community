# frozen_string_literal: true

# Leads novos (contatos criados no período, sem contatos internos), origem e funil de pipeline.
module BusinessAssistant
  module Queries
    class Leads
      TOP_SOURCES = 10

      def self.new_leads(period)
        Contact.where(created_at: period.range).where.not(id: DailySummary::Exclusion.internal_contact_ids)
      end

      def initialize(period)
        @period = period
      end

      def funnel
        leads = self.class.new_leads(@period)
        total = leads.count
        converted = leads.where(id: Sale.active.select(:contact_id)).count
        {
          new_leads: total,
          converted_leads: converted,
          conversion_pct: Sql.pct(converted, total),
          by_day: by_day(leads),
          by_source: by_source(leads),
          pipelines: pipelines
        }
      end

      private

      def by_day(leads)
        counts = leads.group(Sql.local_date('contacts.created_at')).count.transform_keys(&:to_date)
        @period.dates.map { |date| { date: date.iso8601, count: counts[date] || 0 } }
      end

      def by_source(leads)
        expr = Arel.sql("COALESCE(NULLIF(contacts.additional_attributes ->> 'utm_source', ''), " \
                        "NULLIF(contacts.additional_attributes ->> 'attribution_channel', ''), " \
                        "CASE WHEN COALESCE(contacts.additional_attributes ->> 'ad_id', '') <> '' THEN 'meta_ads' END, " \
                        "'sem_origem')")
        leads.group(expr).order(Arel.sql('COUNT(*) DESC')).limit(TOP_SOURCES).count
             .map { |source, count| { source: source, count: count } }
      end

      # Situação dos funis de venda: cards por etapa hoje e quantos entraram em cada etapa no período.
      def pipelines
        Pipeline.where.not(pipeline_type: 'support').includes(:pipeline_stages).map do |pipeline|
          { id: pipeline.id, name: pipeline.name, stages: pipeline_stages(pipeline) }
        end
      end

      def pipeline_stages(pipeline)
        counts = PipelineItem.where(pipeline_id: pipeline.id).group(:pipeline_stage_id).count
        moved = StageMovement.joins(:pipeline_item).where(pipeline_items: { pipeline_id: pipeline.id })
                             .where(created_at: @period.range).group(:to_stage_id).count
        pipeline.pipeline_stages.sort_by(&:position).map do |stage|
          { name: stage.name, type: stage.stage_type, items: counts[stage.id] || 0, entered_in_period: moved[stage.id] || 0 }
        end
      end
    end
  end
end
