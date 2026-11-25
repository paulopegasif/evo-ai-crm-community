# frozen_string_literal: true

# Projeção de faturamento do mês. Com histórico suficiente usa o ritmo por dia da semana das
# últimas 8 semanas; senão, a média diária do mês até hoje. Meta e ritmo necessário vêm do
# mesmo serviço do Painel do Dia, para os números baterem.
module BusinessAssistant
  module Analytics
    class MonthProjection
      HISTORY_WEEKS = 8
      MIN_HISTORY_DAYS_WITH_SALES = 10

      def initialize(today: ::Sales::TimeZone.today)
        @today = today
        @month = today.beginning_of_month
      end

      def call
        progress = SalesGoals::ProgressService.new(month: @month, goal: SalesGoal.general.for_month(@month).first,
                                                   today: @today).call
        sold = progress[:sold].to_d
        method, future = weekday_history? ? ['weekday_pace', weekday_projection] : ['linear', linear_projection(sold)]

        {
          month: @month.strftime('%Y-%m'), today: @today.iso8601, method: method,
          sold: Sql.money(sold), sales_count: progress[:count],
          days_elapsed: @today.day, days_remaining_after_today: days_after_today.size,
          projected: Sql.money(sold + future),
          same_period_last_month: same_period_last_month
        }.merge(goal_fields(progress, sold + future))
      end

      private

      def goal_fields(progress, projected)
        goal = progress[:goal]&.to_d
        {
          goal: goal && Sql.money(goal),
          projected_pct_of_goal: goal&.positive? ? Sql.pct(projected, goal) : nil,
          projected_gap_to_goal: goal && Sql.money(projected - goal),
          remaining_to_goal: progress[:remaining], daily_needed: progress[:daily_pace],
          goal_reached: progress[:goal_reached]
        }
      end

      def days_after_today
        ((@today + 1)..@today.end_of_month).to_a
      end

      def linear_projection(sold)
        (sold / @today.day) * days_after_today.size
      end

      def history_range
        start = @today - (HISTORY_WEEKS * 7)
        zone = ::Sales::TimeZone.current
        zone.local(start.year, start.month, start.day)..zone.local(@today.year, @today.month, @today.day)
      end

      def history_scope
        Sale.active.between(history_range)
      end

      def weekday_history?
        history_scope.distinct.count(Sql.local_date('sales.sold_at')) >= MIN_HISTORY_DAYS_WITH_SALES
      end

      # Média por dia da semana (0 = domingo) nas últimas 8 semanas, sem contar hoje.
      def weekday_projection
        dow = Arel.sql("EXTRACT(DOW FROM #{Sql.local_date('sales.sold_at')})::int")
        averages = history_scope.group(dow).sum(:amount).transform_values { |total| total.to_d / HISTORY_WEEKS }
        days_after_today.sum { |date| averages[date.wday] || 0 }
      end

      def same_period_last_month
        prev = @month.prev_month
        last_day = [@today.day, prev.end_of_month.day].min
        period = Period.new(prev, prev.change(day: last_day), 'same_period_last_month')
        scope = Sale.active.between(period.range)
        { from: period.from.iso8601, to: period.to.iso8601, total: Sql.money(scope.sum(:amount)), count: scope.count }
      end
    end
  end
end
