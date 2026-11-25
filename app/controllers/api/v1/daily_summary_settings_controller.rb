# frozen_string_literal: true

class Api::V1::DailySummarySettingsController < Api::V1::BaseController
  include PainelDoDiaAccess

  before_action :require_admin!

  def show
    success_response(data: DailySummary::Settings.load.as_json)
  end

  def update
    settings = DailySummary::Settings.load.assign(settings_params)
    if settings.save
      success_response(data: settings.as_json, message: 'Daily summary settings saved')
    else
      error_response(ApiErrorCodes::VALIDATION_ERROR, 'Validation failed',
                     details: format_validation_errors(settings.errors), status: :unprocessable_entity)
    end
  end

  # Envio imediato marcado como teste; não conta como o envio do dia.
  def test
    settings = DailySummary::Settings.load
    unless settings.inbox && settings.phones.any?
      return error_response(ApiErrorCodes::VALIDATION_ERROR, 'Configure a caixa de WhatsApp e ao menos um número',
                            status: :unprocessable_entity)
    end

    success_response(data: DailySummary::Sender.new(settings: settings, test: true).call)
  end

  private

  def settings_params
    raw = params[:daily_summary_settings] || params
    raw.permit(:enabled, :time, :inbox_id, phones: []).to_h.symbolize_keys
  end
end
