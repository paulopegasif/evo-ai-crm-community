# frozen_string_literal: true

# Cria vendas automáticas para cards que JÁ estão em estágio `completed` de pipeline de
# vendas antes do Painel do Dia existir. Data = último movimento para o estágio atual
# (ou updated_at do card). Idempotente: pula cards que já têm venda ativa.
module Sales
  class BackfillService
    Result = Struct.new(:created, :skipped, :total_amount, keyword_init: true)

    def initialize(dry_run: true)
      @dry_run = dry_run
    end

    def call
      result = Result.new(created: 0, skipped: 0, total_amount: 0.to_d)
      won_items.find_each do |item|
        if Sale.active.exists?(pipeline_item_id: item.id)
          result.skipped += 1
          next
        end

        sale = build_sale(item)
        sale.save! unless @dry_run
        result.created += 1
        result.total_amount += sale.amount
      end
      result
    end

    private

    def won_items
      PipelineItem.joins(:pipeline, :pipeline_stage)
                  .where.not(pipelines: { pipeline_type: 'support' })
                  .where(pipeline_stages: { stage_type: PipelineStage.stage_types[:completed] })
                  .includes(:conversation)
    end

    def build_sale(item)
      Sale.new(
        source: 'pipeline',
        amount: Sales::CardValue.for(item),
        sold_at: won_at(item),
        pipeline_item: item,
        contact_id: item.contact&.id,
        conversation_id: item.conversation_id,
        seller_id: item.conversation&.assignee_id
      )
    end

    def won_at(item)
      item.stage_movements.where(to_stage_id: item.pipeline_stage_id).maximum(:created_at) || item.updated_at
    end
  end
end
