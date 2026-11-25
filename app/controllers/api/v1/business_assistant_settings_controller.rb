# frozen_string_literal: true

class Api::V1::BusinessAssistantSettingsController < Api::V1::BaseController
  include SuperAdminAccess

  before_action :require_super_admin!

  def show
    success_response(data: BusinessAssistant::Settings.load.as_json)
  end

  def update
    settings = BusinessAssistant::Settings.load.assign(settings_params)
    if settings.save
      success_response(data: settings.as_json, message: 'Business assistant settings saved')
    else
      error_response(ApiErrorCodes::VALIDATION_ERROR, 'Validation failed',
                     details: format_validation_errors(settings.errors), status: :unprocessable_entity)
    end
  end

  # Evento "ping" assinado para conferir URL, segredo e disponibilidade do n8n.
  def test
    settings = BusinessAssistant::Settings.load
    unless settings.webhook_url.present? && settings.secret_set?
      return error_response(ApiErrorCodes::VALIDATION_ERROR, 'Configure a URL do webhook e o segredo antes de testar',
                            status: :unprocessable_entity)
    end

    result = BusinessAssistant::WebhookClient.new(settings).post(
      event: 'ping', installation_id: settings.installation_id, base_url: BusinessAssistant.base_url,
      sent_at: Time.current.iso8601
    )
    success_response(data: { ok: result.success?, status: result.status, error: result.error, latency_ms: result.latency_ms })
  end

  private

  def settings_params
    raw = params[:business_assistant_settings] || params
    raw.permit(:enabled, :inbox_id, :webhook_url, :monthly_limit, :signing_secret, :regenerate_secret,
               phones: %i[phone name scope]).to_h.symbolize_keys
  end
end
