# frozen_string_literal: true

# Ações reservadas a quem implanta a instalação (papel `super_admin` do evo-auth). Diferente de
# User#administrator?, não inclui dono da conta nem administrador, nem chamadas por service token.
module SuperAdminAccess
  extend ActiveSupport::Concern

  private

  def super_admin?
    Current.user.present? && Current.evo_role_key.to_s == 'super_admin'
  end

  def require_super_admin!
    return if super_admin?

    error_response(ApiErrorCodes::FORBIDDEN, 'Somente o super admin pode fazer isso', status: :forbidden)
  end
end
