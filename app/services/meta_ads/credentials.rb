# frozen_string_literal: true

# Encryption and normalization helpers for the Meta Ads integration secrets.
# The access token is stored as a Fernet token in the hook settings and is
# never serialized back to clients (only `token_hint`).
module MetaAds::Credentials
  module_function

  AD_ACCOUNT_FORMAT = /\A(?:act_)?(\d{5,25})\z/

  def encrypt(token)
    Fernet.generate(InstallationConfig.encryption_key, token.to_s)
  end

  def decrypt(encrypted)
    return nil if encrypted.blank?

    verifier = Fernet.verifier(InstallationConfig.encryption_key, encrypted, enforce_ttl: false)
    verifier.valid? ? verifier.message : nil
  rescue StandardError => e
    Rails.logger.error "MetaAds::Credentials: failed to decrypt access token: #{e.message}"
    nil
  end

  # "EAABwz…xyz9"
  def hint(token)
    token = token.to_s
    return '' if token.blank?
    return '••••' if token.length < 12

    "#{token.first(4)}…#{token.last(4)}"
  end

  # Accepts "act_123" or "123"; returns "act_123" or nil when malformed.
  def normalize_ad_account_id(value)
    match = AD_ACCOUNT_FORMAT.match(value.to_s.strip)
    match ? "act_#{match[1]}" : nil
  end
end
