# frozen_string_literal: true

# Mantém vendas e cards de pipeline de vendas coerentes:
# - card entrou em estágio `completed` sem venda ativa ligada → cria venda automática;
# - card saiu de `completed` → cancela as vendas automáticas ligadas (manuais permanecem).
# Pipelines do tipo `support` são ignorados. Roda dentro da transação do card (savepoint
# próprio), então um conflito no índice único nunca derruba a movimentação do card.
module Sales
  class PipelineSync
    def self.call(pipeline_item, previous_stage_id: nil)
      new(pipeline_item, previous_stage_id).call
    end

    def initialize(pipeline_item, previous_stage_id)
      @item = pipeline_item
      @previous_stage = previous_stage_id && PipelineStage.find_by(id: previous_stage_id)
    end

    def call
      return if support_pipeline?

      if won_now?
        create_automatic_sale
      elsif reopened?
        cancel_automatic_sales
      end
    end

    private

    attr_reader :item, :previous_stage

    def support_pipeline?
      item.pipeline&.pipeline_type == 'support'
    end

    def won_now?
      item.pipeline_stage&.stage_completed? && !previous_stage&.stage_completed?
    end

    def reopened?
      previous_stage&.stage_completed? && !item.pipeline_stage&.stage_completed?
    end

    def create_automatic_sale
      return if Sale.active.exists?(pipeline_item_id: item.id)

      Sale.transaction(requires_new: true) do
        Sale.create!(
          source: 'pipeline',
          amount: card_value,
          sold_at: Time.current,
          pipeline_item: item,
          contact_id: item.contact&.id,
          conversation_id: item.conversation_id,
          seller_id: item.conversation&.assignee_id || Current.user&.id,
          created_by_id: Current.user&.id
        )
      end
    rescue ActiveRecord::RecordNotUnique
      # Outra venda ativa foi ligada ao card no mesmo instante (registro manual): nada a fazer.
      nil
    end

    # Valor do card: serviços (regra do Tracking) → produtos ligados → custom_fields['value'].
    def card_value
      Sales::CardValue.for(item)
    end

    def cancel_automatic_sales
      Sale.active.where(pipeline_item_id: item.id, source: 'pipeline').find_each(&:cancel!)
    end
  end
end
