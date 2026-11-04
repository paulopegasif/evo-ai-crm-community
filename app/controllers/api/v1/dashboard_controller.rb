# frozen_string_literal: true

class Api::V1::DashboardController < Api::V1::BaseController
  require_permissions({
    customer: 'dashboard.read',
    leads: 'dashboard.read',
    lead_list: 'dashboard.read',
    lead_journey: 'dashboard.read'
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
      params: lead_tracking_params
    ).call

    success_response(
      data: leads_data,
      message: 'Lead tracking dashboard data retrieved successfully'
    )
  end

  def lead_list
    service = Dashboard::LeadListService.new(params: lead_tracking_params.merge(params.permit(:page, :per_page, :sort, :order, :q, :step)))
    if params[:format] == 'csv'
      send_data service.to_csv, filename: "leads-#{Date.current.iso8601}.csv", type: 'text/csv; charset=utf-8'
    else
      success_response(data: service.call, message: 'Leads do período')
    end
  end

  def lead_journey
    contact = Contact.find(params.require(:contact_id))
    success_response(data: Dashboard::LeadJourneyService.new(contact: contact).call, message: 'Jornada do lead')
  end

  private

  def lead_tracking_params
    dashboard_params.merge(params.permit(:timezone, :source, :campaign_key, :granularity, :stale_days))
  end

  def dashboard_params
    params.permit(:pipeline_id, :team_id, :inbox_id, :user_id, :category, :status, :since, :until)
  end
end
