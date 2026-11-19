# frozen_string_literal: true

# Validates the token against the WhatsApp Business Account and returns the
# account's dataset, creating it when the account has none (POST
# /{waba_id}/dataset returns the existing id when there is one).
class MetaConversions::ConnectionService
  REQUIRED_PERMISSIONS = %w[whatsapp_business_management whatsapp_business_manage_events].freeze
  WABA_FORMAT = /\A\d{5,25}\z/

  Result = Struct.new(:waba_name, :dataset_id, keyword_init: true)

  def self.valid_id?(value)
    WABA_FORMAT.match?(value.to_s)
  end

  def initialize(access_token:, waba_id:)
    @client = MetaAds::GraphClient.new(access_token: access_token)
    @waba_id = waba_id
  end

  def perform
    check_permissions!
    waba = fetch_waba
    Result.new(waba_name: waba['name'], dataset_id: dataset_id)
  end

  private

  # A System User token answers /me/permissions; when it can't be read, the next calls tell.
  def check_permissions!
    granted = Array(@client.get('me/permissions')['data']).select { |p| p['status'] == 'granted' }.pluck('permission')
    return if granted.empty?

    missing = REQUIRED_PERMISSIONS - granted
    return if missing.empty?

    raise MetaAds::GraphClient::TokenInvalidError, "O token não tem as permissões #{missing.join(', ')}. " \
                                                   'Gere um novo token do usuário do sistema marcando essas permissões.'
  rescue MetaAds::GraphClient::ApiError
    nil
  end

  def fetch_waba
    @client.get(@waba_id, fields: 'id,name')
  rescue MetaAds::GraphClient::TokenInvalidError, MetaAds::GraphClient::ApiError => e
    raise e if e.code == 190

    raise MetaAds::GraphClient::TokenInvalidError.new(
      'O token não acessa esta conta do WhatsApp Business. Confira o ID e se o usuário do sistema ' \
      'recebeu a conta como ativo, com controle total.', code: e.code
    )
  end

  def dataset_id
    existing = @client.get("#{@waba_id}/dataset")
    id = existing['id'].presence || Array(existing['data']).first&.dig('id')
    id.presence || @client.post("#{@waba_id}/dataset")['id']
  rescue MetaAds::GraphClient::TokenInvalidError => e
    raise e if e.code == 190

    raise MetaAds::GraphClient::TokenInvalidError.new(
      'A Meta recusou criar o conjunto de dados (dataset). Confira se o token tem a permissão ' \
      "whatsapp_business_manage_events. (Meta: #{e.message})", code: e.code
    )
  end
end
