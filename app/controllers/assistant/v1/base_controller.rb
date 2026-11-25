# frozen_string_literal: true

# API do assistente de negócio, consumida pelo agente no n8n. Fora de /api/v1: não aceita JWT de
# usuário nem service token, só o token temporário emitido em BusinessAssistant::Token.
class Assistant::V1::BaseController < ActionController::API
  include ApiResponseHelper

  before_action :authenticate_assistant!

  rescue_from ActiveRecord::RecordNotFound do
    error_response(ApiErrorCodes::RESOURCE_NOT_FOUND, 'Not found', status: :not_found)
  end

  rescue_from BusinessAssistant::Period::Invalid, BusinessAssistant::Queries::Customers::InvalidRanking do |error|
    error_response(ApiErrorCodes::INVALID_PARAMETER, error.message, status: :unprocessable_entity)
  end

  private

  attr_reader :assistant_context

  def authenticate_assistant!
    token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
    @assistant_context = BusinessAssistant::Token.verify!(token, settings: assistant_settings)
  rescue BusinessAssistant::Token::Invalid => e
    error_response(ApiErrorCodes::INVALID_TOKEN, "Token do assistente inválido: #{e.message}", status: :unauthorized)
  end

  def assistant_settings
    @assistant_settings ||= BusinessAssistant::Settings.load
  end

  # Conversa do token, conferindo que é da caixa do assistente e do mesmo telefone.
  def token_conversation
    @token_conversation ||= begin
      conversation = Conversation.find_by(id: assistant_context.conversation_id, inbox_id: assistant_settings.inbox_id)
      entry = conversation && BusinessAssistant::Sender.phone_entry(assistant_settings, conversation)
      entry && entry['phone'] == assistant_context.phone ? conversation : nil
    end
  end

  def period(default: 'today')
    @period ||= BusinessAssistant::Period.parse(params.permit(:period, :days, :from, :to), default: default)
  end

  # Envelope comum: dados + período + moeda + cobertura (quando houver atribuição envolvida).
  def render_data(data, period: nil, coverage: nil)
    body = { data: data, currency: BusinessAssistant.currency }
    body[:period] = period.as_json if period
    body[:coverage] = coverage if coverage
    success_response(data: body)
  end

  def format_validation_errors(errors)
    errors.messages.map { |field, messages| { field: field, messages: messages } }
  end
end
