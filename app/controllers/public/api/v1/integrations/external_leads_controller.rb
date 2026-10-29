# frozen_string_literal: true

class Public::Api::V1::Integrations::ExternalLeadsController < Public::Api::V1::BaseController
  def create
    result = ExternalLeads::SyncService.new(params).perform

    if result[:success]
      status = if result.dig(:contact, :action) == 'created' || result.dig(:pipeline_item, :action) == 'created'
                 :created
               else
                 :ok
               end
      render json: result, status: status
    else
      render json: result, status: :unprocessable_entity
    end
  rescue StandardError => e
    Rails.logger.error "ExternalLeadsController error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end
end
