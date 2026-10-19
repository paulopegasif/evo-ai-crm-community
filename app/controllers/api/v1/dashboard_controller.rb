# frozen_string_literal: true

class Api::V1::DashboardController < Api::V1::BaseController
  require_permissions({
    customer: 'dashboard.read',
    leads: 'dashboard.read'
  })

  def customer
    dashboard_data = Dashboard::CustomerDashboardService.new(
      params: dashboard_params
    ).call

    success_response(
      data: dashboard_data,
      message: 'Customer dashboard data retrieved successfully'
    )
  end

  def leads
    leads_data = Dashboard::LeadTrackingService.new(
      params: dashboard_params
    ).call

    success_response(
      data: leads_data,
      message: 'Lead tracking dashboard data retrieved successfully'
    )
  end

  private

  def dashboard_params
    params.permit(:pipeline_id, :team_id, :inbox_id, :user_id, :category, :status, :since, :until)
  end
end
