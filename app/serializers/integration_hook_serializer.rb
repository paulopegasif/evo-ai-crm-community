# frozen_string_literal: true

module IntegrationHookSerializer
  extend self

  # Settings keys holding credentials are never sent to clients (e.g. the Meta Ads
  # access token, stored as `access_token_encrypted`; only `token_hint` is exposed).
  SECRET_SETTING_KEY_PATTERN = /(_encrypted|_secret|token)\z/i

  def serialize(hook, **options)
    return nil unless hook

    {
      id: hook.id,
      app_id: hook.app_id,
      inbox_id: hook.inbox_id,
      status: hook.status,
      settings: public_settings(hook.settings),
      hook_type: hook.hook_type,
      created_at: hook.created_at&.iso8601,
      updated_at: hook.updated_at&.iso8601
    }
  end

  def public_settings(settings)
    (settings || {}).reject { |key, _| key.to_s.match?(SECRET_SETTING_KEY_PATTERN) }
  end

  def serialize_collection(hooks, **options)
    return [] unless hooks

    hooks.map { |hook| serialize(hook, **options) }
  end
end
