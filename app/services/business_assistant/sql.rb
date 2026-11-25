# frozen_string_literal: true

# Pedaços de SQL compartilhados pelas consultas do assistente.
module BusinessAssistant
  module Sql
    ATTRIBUTION_KEYS = %w[ad_id utm_source utm_campaign].freeze

    module_function

    # Data local (fuso da instalação) de uma coluna timestamp gravada em UTC.
    def local_date(column)
      tz = ActiveRecord::Base.connection.quote(Sales::TimeZone.current.tzinfo.name)
      Arel.sql("DATE(timezone(#{tz}, timezone('UTC', #{column})))")
    end

    # Contato com origem identificada (anúncio ou UTM), gravada pelo tracking de leads.
    def attributed_contact_condition(table = 'contacts')
      ATTRIBUTION_KEYS.map { |key| "COALESCE(#{table}.additional_attributes ->> '#{key}', '') <> ''" }.join(' OR ')
    end

    def table_exists?(name)
      ActiveRecord::Base.connection.data_source_exists?(name)
    end

    def ads_data_available?
      table_exists?('meta_ad_insights_daily')
    end

    def money(value)
      value.to_d.round(2).to_f
    end

    def pct(part, total)
      return nil if total.to_i.zero?

      (part.to_f * 100 / total).round(1)
    end
  end
end
