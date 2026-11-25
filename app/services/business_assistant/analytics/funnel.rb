# frozen_string_literal: true

# Funil de conversão dos cards criados no período: quantos chegaram a cada etapa, a taxa de passagem
# entre etapas, ganhos, perdidos e tempo médio até ganhar.
module BusinessAssistant
  module Analytics
    class Funnel
      def initialize(period)
        @period = period
      end

      def call
        { pipelines: Pipeline.where.not(pipeline_type: 'support').includes(:pipeline_stages).map { |p| pipeline_funnel(p) } }
      end

      private

      def pipeline_funnel(pipeline)
        stages = pipeline.pipeline_stages.sort_by(&:position)
        items = PipelineItem.where(pipeline_id: pipeline.id, created_at: @period.range).to_a
        reached = reached_positions(items, stages)
        ladder = stages.reject(&:stage_cancelled?)
        won = items.select { |item| stage_type(stages, item) == 'completed' }

        {
          id: pipeline.id, name: pipeline.name, items_created: items.size,
          won: won.size, lost: items.count { |item| stage_type(stages, item) == 'cancelled' },
          win_rate_pct: Sql.pct(won.size, items.size),
          avg_days_to_win: avg_days_to_win(won),
          stages: ladder_rows(ladder, reached)
        }
      end

      def ladder_rows(ladder, reached)
        previous = nil
        ladder.map do |stage|
          count = reached.count { |position| position >= stage.position }
          row = { name: stage.name, type: stage.stage_type, reached: count,
                  conversion_from_previous_pct: previous ? Sql.pct(count, previous) : nil }
          previous = count
          row
        end
      end

      # Maior posição atingida por card na escada (etapa atual ou por onde passou). Etapas de perda
      # não contam; todo card chegou ao menos à primeira etapa.
      def reached_positions(items, stages)
        ladder = stages.reject(&:stage_cancelled?)
        position = ladder.to_h { |s| [s.id, s.position] }
        floor = ladder.first&.position.to_i
        visited = visited_stages(items)
        items.map { |item| ([item.pipeline_stage_id] + visited[item.id]).filter_map { |id| position[id] }.push(floor).max }
      end

      def visited_stages(items)
        StageMovement.where(pipeline_item_id: items.map(&:id)).pluck(:pipeline_item_id, :to_stage_id)
                     .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(item_id, stage_id), acc| acc[item_id] << stage_id }
      end

      def stage_type(stages, item)
        stages.find { |s| s.id == item.pipeline_stage_id }&.stage_type
      end

      def avg_days_to_win(won)
        durations = won.filter_map { |item| item.completed_at && ((item.completed_at - item.created_at) / 1.day) }
        durations.empty? ? nil : (durations.sum / durations.size).round(1)
      end
    end
  end
end
