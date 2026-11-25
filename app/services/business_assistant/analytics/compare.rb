# frozen_string_literal: true

# Compara dois períodos lado a lado (por padrão, o período informado contra o imediatamente anterior).
module BusinessAssistant
  module Analytics
    class Compare
      def initialize(current, previous = nil)
        @current = current
        @previous = previous || current.previous
      end

      def call
        a = metrics(@current)
        b = metrics(@previous)
        {
          current: { period: @current.as_json, metrics: a },
          previous: { period: @previous.as_json, metrics: b },
          variation: a.keys.index_with { |key| variation(a[key], b[key]) }
        }
      end

      private

      def metrics(period)
        sales = Sale.active.between(period.range)
        count = sales.count
        total = sales.sum(:amount)
        leads = Queries::Leads.new_leads(period).count
        result = {
          sales_count: count, sales_total: Sql.money(total),
          average_ticket: count.zero? ? 0.0 : Sql.money(total / count),
          new_leads: leads,
          lead_to_sale_pct: Sql.pct(count, leads)
        }
        result[:ads_spend] = Queries::Ads.new(period).spend[:spend] if Sql.ads_data_available?
        result
      end

      def variation(current, previous)
        return nil if current.nil? || previous.nil?

        diff = current - previous
        { absolute: diff.is_a?(Float) ? diff.round(2) : diff, pct: previous.to_f.zero? ? nil : ((diff / previous.to_f) * 100).round(1) }
      end
    end
  end
end
