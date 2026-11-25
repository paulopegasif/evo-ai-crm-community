# frozen_string_literal: true

# Período pedido pelo agente, sempre no fuso da instalação. Aceita um nome (`period`),
# os últimos N dias (`days`) ou um intervalo (`from`/`to`, datas ISO).
module BusinessAssistant
  class Period
    NAMED = %w[today yesterday this_week last_week this_month last_month last_7_days last_30_days last_90_days].freeze
    MAX_DAYS = 400

    class Invalid < StandardError; end

    attr_reader :from, :to, :label

    def self.parse(params, default: 'today', today: Sales::TimeZone.today)
      params = params.to_h.with_indifferent_access
      if params[:from].present? || params[:to].present?
        between(parse_date(params[:from], 'from'), parse_date(params[:to] || today.iso8601, 'to'))
      elsif params[:days].present?
        last_days(Integer(params[:days].to_s, 10), today)
      else
        named(params[:period].presence || default, today)
      end
    rescue ArgumentError
      raise Invalid, 'days deve ser um número inteiro'
    end

    def self.named(name, today = Sales::TimeZone.today)
      raise Invalid, "period inválido (use: #{NAMED.join(', ')}, days ou from/to)" unless NAMED.include?(name.to_s)
      return last_days(name.to_s[/\d+/].to_i, today, name) if name.to_s.start_with?('last_') && name.to_s.end_with?('_days')

      from, to = named_bounds(name.to_s, today)
      new(from, to, name)
    end

    def self.named_bounds(name, today)
      case name
      when 'today' then [today, today]
      when 'yesterday' then [today - 1, today - 1]
      when 'this_week' then [today.beginning_of_week, today]
      when 'last_week' then [(today - 7).beginning_of_week, (today - 7).end_of_week]
      when 'this_month' then [today.beginning_of_month, today]
      else [today.prev_month.beginning_of_month, today.prev_month.end_of_month]
      end
    end

    def self.last_days(days, today = Sales::TimeZone.today, label = nil)
      raise Invalid, "days deve estar entre 1 e #{MAX_DAYS}" unless days.between?(1, MAX_DAYS)

      new(today - (days - 1), today, label || "last_#{days}_days")
    end

    def self.between(from, to)
      raise Invalid, 'from deve ser anterior ou igual a to' if from > to
      raise Invalid, "intervalo máximo de #{MAX_DAYS} dias" if (to - from).to_i >= MAX_DAYS

      new(from, to, 'custom')
    end

    def self.parse_date(value, field)
      Date.iso8601(value.to_s)
    rescue Date::Error
      raise Invalid, "#{field} deve ser uma data no formato AAAA-MM-DD"
    end

    def initialize(from, to, label)
      @from = from
      @to = to
      @label = label.to_s
    end

    def range
      zone = Sales::TimeZone.current
      zone.local(from.year, from.month, from.day).beginning_of_day..zone.local(to.year, to.month, to.day).end_of_day
    end

    def days
      (to - from).to_i + 1
    end

    def dates
      (from..to).to_a
    end

    # Período imediatamente anterior, de mesma duração.
    def previous
      self.class.new(from - days, from - 1, "previous_#{label}")
    end

    def as_json(*)
      { from: from.iso8601, to: to.iso8601, label: label, days: days, timezone: Sales::TimeZone.current.tzinfo.name }
    end
  end
end
