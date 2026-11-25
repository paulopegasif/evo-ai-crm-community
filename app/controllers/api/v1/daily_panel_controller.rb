# frozen_string_literal: true

class Api::V1::DailyPanelController < Api::V1::BaseController
  include PainelDoDiaAccess

  before_action :require_admin!, only: :update_settings

  def show
    data = DailyPanel::BuildService.new(user: Current.user, admin: current_admin?).call
    success_response(data: data)
  end

  def preferences
    success_response(data: preferences_payload)
  end

  def update_preferences
    category = params[:daily_quote_category].presence
    if category && DailyPanel::QuotePicker::ALL_CHOICES.exclude?(category)
      return error_response(ApiErrorCodes::VALIDATION_ERROR, 'Categoria inválida', status: :unprocessable_entity)
    end

    user = Current.user
    settings = (user.ui_settings || {}).dup
    category ? settings['daily_quote_category'] = category : settings.delete('daily_quote_category')
    user.update!(ui_settings: settings)
    success_response(data: preferences_payload)
  end

  def update_settings
    category = params[:default_quote_category].to_s
    unless DailyPanel::QuotePicker::ALL_CHOICES.include?(category)
      return error_response(ApiErrorCodes::VALIDATION_ERROR, 'Categoria inválida', status: :unprocessable_entity)
    end

    GlobalConfig.set('DAILY_QUOTE_DEFAULT_CATEGORY', category)
    success_response(data: preferences_payload)
  end

  private

  def preferences_payload
    chosen = Current.user&.ui_settings&.dig('daily_quote_category')
    {
      daily_quote_category: DailyPanel::QuotePicker::ALL_CHOICES.include?(chosen) ? chosen : nil,
      default_quote_category: DailyPanel::QuotePicker.default_category,
      categories: DailyPanel::QuotePicker::ALL_CHOICES
    }
  end
end
