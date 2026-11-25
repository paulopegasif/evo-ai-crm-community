# frozen_string_literal: true

# Registro manual de venda (botão "Registrar venda" da conversa). Se o contato tiver um card
# ativo em pipeline de vendas, a venda é ligada a ele e o card vai para o primeiro estágio
# `completed` do pipeline — a venda é criada antes do movimento, então o PipelineSync não
# gera uma segunda venda.
module Sales
  class RegisterService
    def initialize(attributes:, user:)
      @attributes = attributes.to_h.symbolize_keys
      @user = user
    end

    def call
      sale = build_sale
      Sale.transaction do
        card = open_sales_card(sale)
        won_stage = card && first_completed_stage(card)
        sale.pipeline_item = card if won_stage
        sale.save!
        card.move_to_stage(won_stage, user) if won_stage
      end
      sale
    end

    private

    attr_reader :attributes, :user

    def build_sale
      conversation = attributes[:conversation_id].presence && Conversation.find_by(id: attributes[:conversation_id])
      contact_id = attributes[:contact_id].presence || conversation&.contact_id

      Sale.new(
        source: 'manual',
        amount: attributes[:amount],
        sold_at: attributes[:sold_at].presence,
        notes: attributes[:notes],
        product_id: attributes[:product_id].presence,
        conversation_id: conversation&.id,
        contact_id: contact_id,
        seller_id: attributes[:seller_id].presence || user&.id,
        created_by_id: user&.id
      )
    end

    def open_sales_card(sale)
      return if sale.conversation_id.blank? && sale.contact_id.blank?

      conversation_ids = [sale.conversation_id]
      conversation_ids += Conversation.where(contact_id: sale.contact_id).pluck(:id) if sale.contact_id
      conversation_ids = conversation_ids.compact.uniq

      PipelineItem.joins(:pipeline, :pipeline_stage)
                  .where.not(pipelines: { pipeline_type: 'support' })
                  .where(pipeline_stages: { stage_type: PipelineStage.stage_types[:active] })
                  .where('pipeline_items.conversation_id IN (:conv) OR pipeline_items.contact_id = :contact',
                         conv: conversation_ids.presence || [nil], contact: sale.contact_id)
                  .order('pipeline_items.updated_at DESC')
                  .first
    end

    def first_completed_stage(card)
      card.pipeline.pipeline_stages.where(stage_type: PipelineStage.stage_types[:completed]).order(:position).first
    end
  end
end
