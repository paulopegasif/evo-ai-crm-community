# frozen_string_literal: true

# Conversions API for Business Messaging: connection settings, test events and
# delivery status. Saving validates the token against the WhatsApp Business
# Account and creates (or reuses) its dataset. The token is stored encrypted and
# never returned; responses only carry `token_hint`.
class Api::V1::Integrations::MetaConversionsController < Api::V1::BaseController
  require_permissions({
                        show: 'integrations.read',
                        update: 'integrations.update',
                        test_connection: 'integrations.update',
                        test_event: 'integrations.update',
                        destroy: 'integrations.delete'
                      })

  before_action :fetch_integration, only: [:test_connection, :test_event, :destroy]

  def show
    render_integration(MetaConversions::Integration.current)
  end

  def update
    integration = MetaConversions::Integration.find_or_initialize
    waba_id = permitted_params[:waba_id].to_s.strip
    page_id = permitted_params[:page_id].to_s.strip
    invalid = id_error(waba_id, page_id)
    return validation_error(invalid) if invalid

    token_source = permitted_params[:token_source] == 'meta_ads' ? 'meta_ads' : 'own'
    access_token = resolve_token(integration, token_source)
    return validation_error(token_missing_message(token_source)) if access_token.blank?

    result = MetaConversions::ConnectionService.new(access_token: access_token, waba_id: waba_id).perform
    integration.write!(settings_for(waba_id, page_id, token_source, result))
    render_integration(integration, message: 'Conversões da Meta configuradas')
  rescue MetaAds::GraphClient::Error => e
    meta_error(e)
  end

  def test_connection
    result = MetaConversions::ConnectionService.new(access_token: @integration.access_token, waba_id: @integration.waba_id).perform
    @integration.write!('waba_name' => result.waba_name, 'dataset_id' => result.dataset_id,
                        'connection_status' => MetaConversions::Integration::STATUS_CONNECTED, 'last_error' => nil)
    render_integration(@integration, message: 'Conexão com a Meta funcionando')
  rescue MetaAds::GraphClient::Error => e
    @integration.record_error!(e)
    meta_error(e)
  end

  def test_event
    if @integration.dataset_id.blank? || @integration.access_token.blank?
      return validation_error('Salve a configuração antes de enviar um evento de teste.')
    end
    if @integration.test_event_code.blank?
      return validation_error('Informe o código de teste do Gerenciador de Eventos antes de enviar um evento de teste.')
    end

    result = MetaConversions::TestEventService.new(event: params[:event]).perform
    success_response(data: result.to_h, message: result.success ? 'Evento de teste enviado' : 'A Meta recusou o evento de teste')
  end

  # Stops sending; the per-contact delivery log is kept.
  def destroy
    @integration.hook.destroy!
    success_response(data: MetaConversions::Integration.empty_json, message: 'Conversões da Meta desconectadas')
  end

  private

  def fetch_integration
    @integration = MetaConversions::Integration.current
    return if @integration

    error_response(ApiErrorCodes::RESOURCE_NOT_FOUND, 'Conversões da Meta não configuradas.', status: :not_found)
  end

  def id_error(waba_id, page_id)
    return 'ID da conta do WhatsApp Business inválido (só números).' unless MetaConversions::ConnectionService.valid_id?(waba_id)

    'ID da Página inválido (só números).' if page_id.present? && !MetaConversions::ConnectionService.valid_id?(page_id)
  end

  # A blank token keeps the stored one.
  def resolve_token(integration, token_source)
    return MetaAds::Integration.current&.access_token if token_source == 'meta_ads'

    permitted_params[:access_token].to_s.strip.presence ||
      (integration.token_source == 'own' ? MetaAds::Credentials.decrypt(integration.settings[:access_token_encrypted]) : nil)
  end

  def token_missing_message(token_source)
    return 'Conecte a integração Meta Ads antes de reaproveitar o token dela.' if token_source == 'meta_ads'

    'Informe o token de acesso.'
  end

  def settings_for(waba_id, page_id, token_source, result)
    token = permitted_params[:access_token].to_s.strip
    {
      'waba_id' => waba_id,
      'page_id' => page_id.presence,
      'waba_name' => result.waba_name,
      'dataset_id' => result.dataset_id,
      'token_source' => token_source,
      **(token.present? && token_source == 'own' ? token_settings(token) : {}),
      **(token_source == 'meta_ads' ? { 'access_token_encrypted' => nil, 'token_hint' => nil } : {}),
      'test_event_code' => permitted_params[:test_event_code].to_s.strip.presence,
      'event_names' => event_names,
      'enabled' => ActiveModel::Type::Boolean.new.cast(permitted_params[:enabled]) == true,
      'connection_status' => MetaConversions::Integration::STATUS_CONNECTED,
      'last_error' => nil,
      'connected_at' => Time.current.iso8601
    }
  end

  def token_settings(token)
    { 'access_token_encrypted' => MetaAds::Credentials.encrypt(token), 'token_hint' => MetaAds::Credentials.hint(token) }
  end

  # Only names that differ from the default are stored.
  def event_names
    given = permitted_params[:event_names].to_h
    MetaConversions::Integration::EVENTS.each_with_object({}) do |event, names|
      name = given[event].to_s.strip
      names[event] = name if name.present? && name != MetaConversions::Config::DEFAULT_EVENT_NAMES[event]
    end
  end

  def permitted_params
    params.permit(:waba_id, :page_id, :access_token, :token_source, :test_event_code, :enabled,
                  event_names: MetaConversions::Integration::EVENTS)
  end

  def render_integration(integration, message: 'Meta conversions integration retrieved successfully')
    success_response(data: integration ? integration.as_json : MetaConversions::Integration.empty_json, message: message)
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
