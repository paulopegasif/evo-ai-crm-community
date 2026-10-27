class Integrations::App
  include Linear::IntegrationHelper
  include Hubspot::IntegrationHelper
  attr_accessor :params

  def initialize(params)
    @params = params
  end

  def id
    params[:id]
  end

  def name
    I18n.t("integration_apps.#{params[:i18n_key]}.name")
  end

  def description
    I18n.t("integration_apps.#{params[:i18n_key]}.description")
  end

  def short_description
    I18n.t("integration_apps.#{params[:i18n_key]}.short_description")
  end

  def logo
    params[:logo]
  end

  def fields
    params[:fields]
  end

  # Token generation is used to encode an identifier in the OAuth state parameter
  def encode_state
    case params[:id]
    when 'linear'
      generate_linear_token(nil)
    when 'hubspot'
      generate_hubspot_token(nil)
    else
      nil
    end
  end

  def action
    case params[:id]
    when 'slack'
      client_id = GlobalConfigService.load('SLACK_CLIENT_ID', nil)
      "#{params[:action]}&client_id=#{client_id}&redirect_uri=#{self.class.slack_integration_url}"
    when 'linear'
      build_linear_action
    when 'hubspot'
      build_hubspot_action
    else
      params[:action]
    end
  end

  def active?(_account = nil)
    case params[:id]
    when 'slack'
      GlobalConfigService.load('SLACK_CLIENT_SECRET', nil).present?
    when 'linear'
      GlobalConfigService.load('LINEAR_CLIENT_ID', nil).present?
    when 'hubspot'
      GlobalConfigService.load('HUBSPOT_CLIENT_ID', nil).present?
    when 'shopify'
      GlobalConfigService.load('SHOPIFY_CLIENT_ID', nil).present?
    when 'leadsquared', 'bms', 'google_calendar', 'meta_ads'
      true
    when 'webhook', 'dashboard_apps', 'openai'
      true
    when 'oauth_applications'
      false
    else
      false
    end
  end

  def build_linear_action
    app_id = GlobalConfigService.load('LINEAR_CLIENT_ID', nil)
    [
      "#{params[:action]}?response_type=code",
      "client_id=#{app_id}",
      "redirect_uri=#{self.class.linear_integration_url}",
      "state=#{encode_state}",
      'scope=read,write',
      'prompt=consent'
    ].join('&')
  end

  def build_hubspot_action
    app_id = GlobalConfigService.load('HUBSPOT_CLIENT_ID', nil)
    [
      "#{params[:action]}?response_type=code",
      "client_id=#{app_id}",
      "redirect_uri=#{self.class.hubspot_integration_url}",
      "state=#{encode_state}",
      'scope=crm.objects.contacts.read crm.objects.contacts.write crm.objects.deals.read crm.objects.deals.write crm.objects.companies.read crm.objects.companies.write crm.objects.line_items.read crm.objects.owners.read crm.schemas.deals.read oauth settings.users.read'
    ].join('&')
  end

  def enabled?(_account = nil)
    case params[:id]
    when 'webhook'
      Webhook.exists?
    when 'dashboard_apps'
      DashboardApp.exists?
    when 'oauth_applications'
      OauthApplication.exists?
    else
      Integrations::Hook.exists?(app_id: id)
    end
  end

  def hooks
    Integrations::Hook.where(app_id: id)
  end

  def self.slack_integration_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/app/settings/integrations/slack"
  end

  def self.linear_integration_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/linear/callback"
  end

  def self.hubspot_integration_url
    "#{ENV.fetch('FRONTEND_URL', nil)}/hubspot/callback"
  end

  class << self
    def apps
      Hashie::Mash.new(APPS_CONFIG)
    end

    def all
      apps.values.each_with_object([]) do |app, result|
        result << new(app)
      end
    end

    def find(params)
      all.detect { |app| app.id == params[:id] }
    end
  end
end
