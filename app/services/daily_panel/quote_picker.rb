# frozen_string_literal: true

# Frase do dia: lista estática (config/daily_quotes/pt_BR.yml), escolha determinística por
# data e categoria — todos os usuários com a mesma categoria veem a mesma frase no dia.
module DailyPanel
  module QuotePicker
    CATEGORIES = %w[motivacao negocios biblia].freeze
    OFF = 'off'
    ALL_CHOICES = (CATEGORIES + [OFF]).freeze
    DEFAULT_CATEGORY = 'motivacao'

    module_function

    def pick(category, date: Sales::TimeZone.today)
      return nil if category.blank? || category == OFF

      list = quotes[category.to_s]
      return nil if list.blank?

      item = list[(date.yday + date.year) % list.size]
      { text: item['text'], author: item['author'] || item['ref'], category: category.to_s }
    end

    def quotes
      @quotes ||= YAML.safe_load_file(Rails.root.join('config/daily_quotes/pt_BR.yml')).slice(*CATEGORIES)
    end

    # Preferência do usuário (ui_settings) → padrão da instalação → motivação.
    def category_for(user)
      chosen = user&.ui_settings&.dig('daily_quote_category')
      return chosen if ALL_CHOICES.include?(chosen)

      default_category
    end

    def default_category
      value = GlobalConfig.get_value('DAILY_QUOTE_DEFAULT_CATEGORY')
      ALL_CHOICES.include?(value) ? value : DEFAULT_CATEGORY
    rescue StandardError
      DEFAULT_CATEGORY
    end
  end
end
