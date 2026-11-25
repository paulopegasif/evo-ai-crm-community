# frozen_string_literal: true

module SaleSerializer
  extend self

  def serialize(sale)
    {
      id: sale.id,
      amount: sale.amount.to_f,
      sold_at: sale.sold_at&.iso8601,
      status: sale.status,
      source: sale.source,
      missing_amount: sale.missing_amount,
      notes: sale.notes,
      seller: sale.seller && { id: sale.seller.id, name: sale.seller.name },
      created_by_id: sale.created_by_id,
      contact: sale.contact && { id: sale.contact.id, name: sale.contact.name },
      conversation_id: sale.conversation_id,
      pipeline_item_id: sale.pipeline_item_id,
      product: sale.product && { id: sale.product.id, name: sale.product.name },
      cancelled_at: sale.cancelled_at&.iso8601,
      created_at: sale.created_at&.iso8601
    }
  end

  def serialize_collection(sales)
    sales.map { |sale| serialize(sale) }
  end
end
