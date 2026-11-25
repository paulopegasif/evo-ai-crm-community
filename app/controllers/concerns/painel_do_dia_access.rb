# frozen_string_literal: true

# Regras de acesso dos endpoints do Painel do Dia. O CRM não usa chaves de permissão do
# evo-auth aqui: administrador = papel admin (User#administrator?); demais usuários só
# enxergam/alteram o que é deles.
module PainelDoDiaAccess
  extend ActiveSupport::Concern

  private

  def current_admin?
    Current.service_authenticated == true || Current.user&.administrator?
  end

  def require_admin!
    return if current_admin?

    error_response(ApiErrorCodes::FORBIDDEN, 'Somente administradores podem fazer isso', status: :forbidden)
  end

  def record_validation_error(record)
    error_response(ApiErrorCodes::VALIDATION_ERROR, 'Validation failed',
                   details: format_validation_errors(record.errors), status: :unprocessable_entity)
  end

  def not_found(message = 'Not found')
    error_response(ApiErrorCodes::RESOURCE_NOT_FOUND, message, status: :not_found)
  end
end
