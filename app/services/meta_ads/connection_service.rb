# frozen_string_literal: true

# Validates a token against an ad account before it is persisted.
# Returns the account metadata shown on the integration page.
class MetaAds::ConnectionService
  REQUIRED_PERMISSION_MESSAGE = 'O token não tem acesso de leitura a esta conta de anúncios. ' \
                                'Verifique se o System User foi adicionado à conta com a permissão ads_read.'

  Result = Struct.new(:account_name, :currency, :timezone_name, :account_status, keyword_init: true)

  def initialize(access_token:, ad_account_id:)
    @client = MetaAds::GraphClient.new(access_token: access_token)
    @ad_account_id = ad_account_id
  end

  def perform
    @client.get('me', fields: 'id,name')
    account = fetch_account

    Result.new(
      account_name: account['name'],
      currency: account['currency'],
      timezone_name: account['timezone_name'],
      account_status: account['account_status']
    )
  end

  private

  def fetch_account
    @client.get(@ad_account_id, fields: 'name,currency,timezone_name,account_status')
  rescue MetaAds::GraphClient::TokenInvalidError => e
    # Code 190 is a dead token; anything else here is a valid token without access to the account.
    raise e if e.code == 190

    raise MetaAds::GraphClient::TokenInvalidError.new(REQUIRED_PERMISSION_MESSAGE, code: e.code, subcode: e.subcode)
  rescue MetaAds::GraphClient::ApiError => e
    # Unknown/inaccessible object ids come back as code 100.
    raise MetaAds::GraphClient::TokenInvalidError.new(REQUIRED_PERMISSION_MESSAGE, code: e.code) if e.code == 100

    raise e
  end
end
