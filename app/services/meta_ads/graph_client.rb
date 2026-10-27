# frozen_string_literal: true

# Minimal read-only client for the Meta Graph / Marketing API.
# https://developers.facebook.com/docs/marketing-api/reference
class MetaAds::GraphClient
  class Error < StandardError
    attr_reader :code, :subcode

    def initialize(message, code: nil, subcode: nil)
      super(message)
      @code = code
      @subcode = subcode
    end
  end

  # Expired, revoked or under-privileged token: requires a new token from the user.
  class TokenInvalidError < Error; end
  # Throttled: retry on the next scheduled run.
  class RateLimitedError < Error; end
  class ApiError < Error; end

  BASE_URL = 'https://graph.facebook.com'
  DEFAULT_VERSION = 'v24.0'
  TOKEN_ERROR_CODES = [102, 190].freeze
  PERMISSION_ERROR_CODES = [10, 200].freeze
  RATE_LIMIT_ERROR_CODES = [4, 17, 32, 613, 80_000, 80_004].freeze
  TIMEOUT = 30
  LOCALIZED_MESSAGES = {
    190 => 'Token de acesso inválido, expirado ou revogado.',
    102 => 'Sessão do token inválida.',
    4 => 'Limite de requisições da Meta atingido; a próxima sincronização tenta novamente.',
    17 => 'Limite de requisições da Meta atingido; a próxima sincronização tenta novamente.',
    32 => 'Limite de requisições da Meta atingido; a próxima sincronização tenta novamente.',
    613 => 'Limite de requisições da Meta atingido; a próxima sincronização tenta novamente.',
    80_004 => 'Limite de requisições da Meta atingido; a próxima sincronização tenta novamente.'
  }.freeze

  def initialize(access_token:, version: nil, app_secret: nil)
    @access_token = access_token
    @version = version.presence || GlobalConfigService.load('META_GRAPH_API_VERSION', nil).presence || DEFAULT_VERSION
    @app_secret = app_secret.presence || GlobalConfigService.load('META_APP_SECRET', nil).presence
  end

  attr_reader :version

  def get(path, params = {})
    request("#{BASE_URL}/#{@version}/#{path.to_s.delete_prefix('/')}", params.merge(auth_params))
  end

  # Follows `paging.next` until the end, yielding each item.
  def each_page_item(path, params = {}, &block)
    return enum_for(:each_page_item, path, params) unless block

    body = get(path, params)
    loop do
      Array(body['data']).each(&block)
      next_url = body.dig('paging', 'next')
      break if next_url.blank?

      # `next` already carries every query param, including the access token.
      body = request(next_url, {})
    end
  end

  private

  def auth_params
    params = { access_token: @access_token }
    params[:appsecret_proof] = OpenSSL::HMAC.hexdigest('SHA256', @app_secret, @access_token) if @app_secret
    params
  end

  def request(url, query)
    response = HTTParty.get(url, query: query, timeout: TIMEOUT)
    body = parse(response)
    raise_error(body['error'], response.code) if body['error'] || !response.success?

    body
  rescue HTTParty::Error, Timeout::Error, SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
    raise ApiError, "Falha de comunicação com a Meta: #{e.message}"
  end

  def parse(response)
    parsed = response.parsed_response
    parsed.is_a?(Hash) ? parsed : JSON.parse(response.body.to_s)
  rescue JSON::ParserError
    {}
  end

  def raise_error(error, http_status)
    error ||= {}
    code = error['code']
    subcode = error['error_subcode']
    meta_message = error['error_user_msg'].presence || error['message'].presence || "Erro HTTP #{http_status} da Meta"
    message = LOCALIZED_MESSAGES[code] ? "#{LOCALIZED_MESSAGES[code]} (Meta: #{meta_message})" : meta_message

    raise error_class(code).new(message, code: code, subcode: subcode)
  end

  def error_class(code)
    return TokenInvalidError if TOKEN_ERROR_CODES.include?(code) || PERMISSION_ERROR_CODES.include?(code)
    return RateLimitedError if RATE_LIMIT_ERROR_CODES.include?(code)

    ApiError
  end
end
