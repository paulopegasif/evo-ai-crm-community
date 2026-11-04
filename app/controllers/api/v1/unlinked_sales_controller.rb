# frozen_string_literal: true

# Review queue for external sales that could not be tied to a lead.
class Api::V1::UnlinkedSalesController < Api::V1::BaseController
  require_permissions({
    index: 'dashboard.read',
    link: 'dashboard.read',
    create_lead: 'dashboard.read',
    dismiss: 'dashboard.read'
  })

  before_action :set_sale, only: %i[link create_lead dismiss]

  def index
    scope = UnlinkedSale.where(status: params[:status].presence || 'pending').order(sold_at: :desc)
    sales = scope.page(params[:page]).per(params[:per_page].presence || 50)
    success_response(
      data: {
        sales: sales.map { |sale| serialize(sale) },
        meta: { page: sales.current_page, total_pages: sales.total_pages, total_count: sales.total_count }
      },
      message: 'Vendas para revisão'
    )
  end

  # Ties the sale to an existing lead and replays the sync so the appointment,
  # card and revenue land on that lead. Later syncs keep this link.
  def link
    contact = Contact.find(params.require(:contact_id))
    resolve!(contact, 'linked')
  end

  # No lead exists: creates one from the sale data.
  def create_lead
    contact = Contact.new(name: @sale.customer_name, phone_number: @sale.customer_phone.presence)
    contact.created_at = @sale.sold_at if @sale.sold_at
    contact.save!
    resolve!(contact, 'created')
  end

  def dismiss
    @sale.update!(status: 'dismissed', resolved_at: Time.current)
    success_response(data: serialize(@sale), message: 'Venda descartada')
  end

  private

  def set_sale
    @sale = UnlinkedSale.find(params[:id])
  end

  def resolve!(contact, status)
    result = UnlinkedSales::ResolveService.new(sale: @sale, contact: contact, status: status).perform
    return success_response(data: serialize(@sale.reload), message: 'Venda ligada ao lead') if result[:success]

    error_response(ApiErrorCodes::VALIDATION_ERROR, 'Não foi possível ligar a venda', details: result[:errors],
                                                                                       status: :unprocessable_entity)
  end

  def serialize(sale)
    {
      id: sale.id, source: sale.source, external_id: sale.external_id, customer_name: sale.customer_name,
      customer_phone: sale.customer_phone, reason: sale.reason, status: sale.status, amount: sale.amount.to_f,
      category: sale.category, sold_at: sale.sold_at&.iso8601, resolved_contact_id: sale.resolved_contact_id,
      candidates: sale.candidates.pluck(:id, :name, :phone_number, :created_at).map do |id, name, phone, created_at|
        { id: id, name: name, phone_number: phone, created_at: created_at.iso8601 }
      end
    }
  end
end
