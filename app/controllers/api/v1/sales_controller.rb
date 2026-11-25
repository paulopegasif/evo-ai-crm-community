# frozen_string_literal: true

class Api::V1::SalesController < Api::V1::BaseController
  include PainelDoDiaAccess

  before_action :require_admin!, only: :sellers
  before_action :fetch_sale, only: %i[update cancel]
  before_action :authorize_change!, only: %i[update cancel]

  def index
    sales = visible_scope.includes(:seller, :contact, :product).order(sold_at: :desc)
    sales = apply_filters(sales)
    page = [params[:page].to_i, 1].max
    per_page = (params[:per_page] || params[:page_size] || params[:pageSize] || 50).to_i.clamp(1, 200)
    sales = sales.page(page).per(per_page)

    paginated_response(data: SaleSerializer.serialize_collection(sales), collection: sales,
                       message: 'Sales retrieved successfully')
  end

  def create
    attrs = sale_params
    attrs[:seller_id] = Current.user&.id unless current_admin? # agente só registra em nome próprio
    sale = Sales::RegisterService.new(attributes: attrs, user: Current.user).call
    success_response(data: SaleSerializer.serialize(sale.reload), message: 'Sale registered', status: :created)
  rescue ActiveRecord::RecordInvalid => e
    record_validation_error(e.record)
  end

  def update
    attrs = sale_params.except(:conversation_id, :contact_id)
    attrs.delete(:seller_id) unless current_admin?
    if @sale.update(attrs)
      success_response(data: SaleSerializer.serialize(@sale.reload), message: 'Sale updated')
    else
      record_validation_error(@sale)
    end
  end

  # Usuários do CRM (ids locais) para o seletor de vendedor — só administradores escolhem vendedor.
  def sellers
    success_response(data: User.order(:name).map { |u| { id: u.id, name: u.name } })
  end

  def cancel
    @sale.cancel!
    success_response(data: SaleSerializer.serialize(@sale.reload), message: 'Sale cancelled')
  end

  private

  def visible_scope
    current_admin? ? Sale.all : Sale.for_seller(Current.user)
  end

  def apply_filters(scope)
    zone = Sales::TimeZone.current
    scope = scope.where('sold_at >= ?', zone.parse(params[:since]).beginning_of_day) if params[:since].present?
    scope = scope.where('sold_at <= ?', zone.parse(params[:until]).end_of_day) if params[:until].present?
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(seller_id: params[:seller_id]) if params[:seller_id].present? && current_admin?
    scope = scope.where(conversation_id: params[:conversation_id]) if params[:conversation_id].present?
    scope
  end

  def fetch_sale
    @sale = visible_scope.find_by(id: params[:id]) || (current_admin? ? nil : Sale.find_by(id: params[:id]))
    not_found('Sale not found') unless @sale
  end

  # Admin altera qualquer venda; demais usuários só as que registraram.
  def authorize_change!
    return if current_admin? || @sale.created_by_id == Current.user&.id

    error_response(ApiErrorCodes::FORBIDDEN, 'Você só pode alterar vendas que registrou', status: :forbidden)
  end

  def sale_params
    params.require(:sale).permit(:amount, :sold_at, :notes, :product_id, :seller_id, :conversation_id, :contact_id)
          .to_h.symbolize_keys
  end
end
