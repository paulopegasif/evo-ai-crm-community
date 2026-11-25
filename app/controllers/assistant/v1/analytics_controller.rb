# frozen_string_literal: true

# Análises calculadas no CRM; a IA interpreta e recomenda, mas não faz as contas.
class Assistant::V1::AnalyticsController < Assistant::V1::BaseController
  rescue_from BusinessAssistant::Analytics::BudgetSimulation::Invalid do |error|
    error_response(ApiErrorCodes::INVALID_PARAMETER, error.message, status: :unprocessable_entity)
  end

  def month_projection
    render_data(BusinessAssistant::Analytics::MonthProjection.new.call)
  end

  def compare
    other = if params[:compare_from].present? || params[:compare_to].present?
              BusinessAssistant::Period.parse(from: params[:compare_from], to: params[:compare_to])
            end
    render_data(BusinessAssistant::Analytics::Compare.new(period(default: 'last_7_days'), other).call)
  end

  def campaigns
    p = period(default: 'last_30_days')
    render_data(BusinessAssistant::Analytics::Campaigns.new(p).call, period: p,
                                                                     coverage: BusinessAssistant::Coverage.for_period(p))
  end

  def budget_simulation
    p = period(default: 'last_30_days')
    result = BusinessAssistant::Analytics::BudgetSimulation.new(p, budget: params[:budget], campaign_id: params[:campaign_id]).call
    render_data(result, period: p, coverage: BusinessAssistant::Coverage.for_period(p))
  end

  def funnel
    p = period(default: 'last_90_days')
    render_data(BusinessAssistant::Analytics::Funnel.new(p).call, period: p)
  end

  def seasonality
    p = period(default: 'last_90_days')
    render_data(BusinessAssistant::Analytics::Seasonality.new(p).call, period: p)
  end

  def customer_health
    p = period(default: 'last_30_days')
    render_data(BusinessAssistant::Analytics::CustomerHealth.new(p).call, period: p)
  end
end
