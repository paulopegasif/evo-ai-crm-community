# frozen_string_literal: true

# Fuso horário da instalação para agrupar vendas e metas por dia/mês.
# Ordem: InstallationConfig INSTALLATION_TIMEZONE → ENV INSTALLATION_TIMEZONE → America/Sao_Paulo.
module Sales
  module TimeZone
    DEFAULT = 'America/Sao_Paulo'

    module_function

    def current
      name = config_value.presence || ENV.fetch('INSTALLATION_TIMEZONE', nil).presence || DEFAULT
      ActiveSupport::TimeZone[name] || ActiveSupport::TimeZone[DEFAULT]
    end

    def today
      current.today
    end

    def day_range(date)
      zone = current
      zone.parse(date.to_s).all_day
    end

    def month_range(date)
      zone = current
      start = zone.local(date.year, date.month, 1)
      start..start.end_of_month
    end

    def config_value
      GlobalConfig.get_value('INSTALLATION_TIMEZONE')
    rescue StandardError
      nil
    end
  end
end
