# frozen_string_literal: true

class Public::Api::V1::Integrations::ExternalConversationsController < Public::Api::V1::BaseController
  def create
    result = ExternalConversations::MirrorService.new(params).perform
    render json: result, status: result[:success] ? :ok : :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "ExternalConversationsController error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end
end
