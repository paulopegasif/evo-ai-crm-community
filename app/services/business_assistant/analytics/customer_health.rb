# frozen_string_literal: true

# Saúde da carteira: recorrência, intervalo médio entre compras, clientes novos e clientes em risco
# (recorrentes que passaram bem do intervalo habitual sem comprar).
module BusinessAssistant
  module Analytics
    class CustomerHealth
      INACTIVE_AFTER_DAYS = 45
      RISK_FACTOR = 1.5
      AT_RISK_LIMIT = 10

      def initialize(period)
        @period = period
        @today = ::Sales::TimeZone.today
      end

      def call
        stats = customer_stats
        recurring = stats.select { |s| s[:count] >= 2 }
        intervals = recurring.pluck(:interval_days)
        {
          total_customers: stats.size,
          recurring_customers: recurring.size,
          recurring_pct: Sql.pct(recurring.size, stats.size),
          avg_days_between_purchases: intervals.empty? ? nil : (intervals.sum / intervals.size).round(1),
          new_customers_in_period: stats.count { |s| s[:first].to_date.between?(@period.from, @period.to) },
          inactive_customers: stats.count { |s| s[:days_since] >= INACTIVE_AFTER_DAYS },
          at_risk: at_risk(recurring)
        }
      end

      private

      def customer_stats
        rows = Sale.active.where.not(contact_id: nil).where.not(contact_id: DailySummary::Exclusion.internal_contact_ids)
                   .group(:contact_id)
                   .pluck(:contact_id, Arel.sql('COUNT(*)'), Arel.sql('SUM(sales.amount)'), Arel.sql('MIN(sales.sold_at)'),
                          Arel.sql('MAX(sales.sold_at)'))
        rows.map { |row| customer_row(*row) }
      end

      def customer_row(id, count, total, first, last)
        zone = ::Sales::TimeZone.current
        first_local = first.in_time_zone(zone)
        last_local = last.in_time_zone(zone)
        { id: id, count: count, total: total, first: first_local, last: last_local,
          days_since: (@today - last_local.to_date).to_i,
          interval_days: count > 1 ? ((last_local - first_local) / 1.day / (count - 1)).round(1) : nil }
      end

      def at_risk(recurring)
        risky = recurring.select { |s| s[:days_since] >= [INACTIVE_AFTER_DAYS, s[:interval_days] * RISK_FACTOR].max }
                         .sort_by { |s| -s[:total] }.first(AT_RISK_LIMIT)
        names = Contact.where(id: risky.pluck(:id)).pluck(:id, :name, :phone_number).to_h { |id, *rest| [id, rest] }
        risky.map do |s|
          name, phone = names[s[:id]]
          { id: s[:id], name: name, phone: phone, purchases: s[:count], total: Sql.money(s[:total]),
            usual_interval_days: s[:interval_days], days_since_last_purchase: s[:days_since] }
        end
      end
    end
  end
end
