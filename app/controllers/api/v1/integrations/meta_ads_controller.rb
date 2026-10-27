# frozen_string_literal: true

# Meta Ads integration: connection settings, status and manual sync.
# The access token is validated against the Graph API before being stored
# (encrypted) and is never returned — responses only carry `token_hint`.
class Api::V1::Integrations::MetaAdsController < Api::V1::BaseController
  require_permissions({
                        show: 'integrations.read',
                        update: 'integrations.update',
                        test_connection: 'integrations.update',
                        sync: 'integrations.execute',
                        destroy: 'integrations.delete'
                      })

  before_action :fetch_integration, only: [:test_connection, :sync, :destroy]

  def show
    render_integration(MetaAds::Integration.current)
  end

  # Connect or update. A blank access_token keeps the stored one.
  def update
    current = MetaAds::Integration.current
    ad_account_id = MetaAds::Credentials.normalize_ad_account_id(permitted_params[:ad_account_id])
    return validation_error('ID da conta de anúncios inválido. Use o formato act_1234567890.') if ad_account_id.blank?

    access_token = permitted_params[:access_token].to_s.strip.presence || current&.access_token
    return validation_error('Informe o token de acesso.') if access_token.blank?

    account = MetaAds::ConnectionService.new(access_token: access_token, ad_account_id: ad_account_id).perform
    integration = MetaAds::Integration.connect!(ad_account_id: ad_account_id, access_token: access_token, account: account)
    MetaAds::SyncJob.perform_later if integration.never_synced?

    render_integration(integration, message: 'Conta Meta Ads conectada')
  rescue MetaAds::GraphClient::Error => e
    meta_error(e)
  end

  def test_connection
    account = MetaAds::ConnectionService.new(
      access_token: @integration.access_token,
      ad_account_id: @integration.ad_account_id
    ).perform
    @integration.write!(
      'account_name' => account.account_name,
      'currency' => account.currency,
      'timezone_name' => account.timezone_name,
      'connection_status' => MetaAds::Integration::STATUS_CONNECTED,
      'last_error' => nil
    )
    render_integration(@integration, message: 'Conexão com a Meta funcionando')
  rescue MetaAds::GraphClient::TokenInvalidError => e
    @integration.record_error!(e, status: MetaAds::Integration::STATUS_TOKEN_INVALID)
    meta_error(e)
  rescue MetaAds::GraphClient::Error => e
    @integration.record_error!(e)
    meta_error(e)
  end

  def sync
    unless @integration.syncable?
      return error_response(ApiErrorCodes::BUSINESS_RULE_VIOLATION,
                            'Reconecte a conta Meta Ads antes de sincronizar.', status: :unprocessable_entity)
    end
    if MetaAds::SyncLock.locked?
      return error_response(ApiErrorCodes::BUSINESS_RULE_VIOLATION,
                            'Já existe uma sincronização em andamento.', status: :conflict)
    end

    MetaAds::SyncJob.perform_later
    success_response(data: @integration.as_json.merge(sync_in_progress: true), message: 'Sincronização iniciada',
                     status: :accepted)
  end

  # Removes the token and stops syncing; imported campaigns/metrics are kept.
  def destroy
    @integration.hook.destroy!
    success_response(data: MetaAds::Integration.empty_json, message: 'Integração Meta Ads desconectada')
  end

  private

  def fetch_integration
    @integration = MetaAds::Integration.current
    return if @integration

    error_response(ApiErrorCodes::RESOURCE_NOT_FOUND, 'Integração Meta Ads não configurada.', status: :not_found)
  end

  def permitted_params
    params.permit(:ad_account_id, :access_token)
  end

  def render_integration(integration, message: 'Meta Ads integration retrieved successfully')
    success_response(data: integration ? integration.as_json : MetaAds::Integration.empty_json, message: message)
  end

  def validation_error(message)
    error_response(ApiErrorCodes::VALIDATION_ERROR, message, status: :unprocessable_entity)
  end

  def meta_error(error)
    error_response(
      ApiErrorCodes::BUSINESS_RULE_VIOLATION,
      error.message,
      details: { meta_error_code: error.code, token_invalid: error.is_a?(MetaAds::GraphClient::TokenInvalidError) },
      status: :unprocessable_entity
    )
  end
end
