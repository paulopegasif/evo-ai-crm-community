# frozen_string_literal: true

# Em que dias da semana e horários se vende mais (fuso da instalação).
module BusinessAssistant
  module Analytics
    class Seasonality
      WEEKDAYS = %w[domingo segunda terça quarta quinta sexta sábado].freeze

      def initialize(period)
        @period = period
      end

      def call
        weekdays = by_weekday
        hours = by_hour
        {
          by_weekday: weekdays, by_hour: hours,
          best_weekday: weekdays.max_by { |row| row[:total] }&.dig(:weekday),
          best_hour: hours.max_by { |row| row[:total] }&.dig(:hour)
        }
      end

      private

      def local_ts
        tz = ActiveRecord::Base.connection.quote(::Sales::TimeZone.current.tzinfo.name)
        "timezone(#{tz}, timezone('UTC', sales.sold_at))"
      end

      def grouped(part)
        expr = Arel.sql("EXTRACT(#{part} FROM #{local_ts})::int")
        Sale.active.between(@period.range).group(expr).pluck(expr, Arel.sql('COUNT(*)'), Arel.sql('SUM(sales.amount)'))
            .to_h { |key, count, total| [key, [count, total]] }
      end

      def by_weekday
        rows = grouped('DOW')
        occurrences = @period.dates.group_by(&:wday).transform_values(&:size)
        (0..6).map do |dow|
          count, total = rows[dow] || [0, 0]
          { weekday: WEEKDAYS[dow], count: count, total: Sql.money(total),
            average_per_day: Sql.money(total.to_d / [occurrences[dow].to_i, 1].max) }
        end
      end

      def by_hour
        rows = grouped('HOUR')
        (0..23).map do |hour|
          count, total = rows[hour] || [0, 0]
          { hour: hour, count: count, total: Sql.money(total) }
        end
      end
    end
  end
end
