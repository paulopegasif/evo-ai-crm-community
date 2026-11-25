# frozen_string_literal: true

# Resumo de vendas de um período (vendas ativas; canceladas ficam fora).
module BusinessAssistant
  module Queries
    class SalesReport
      TOP = 5

      def initialize(period)
        @period = period
      end

      def scope
        Sale.active.between(@period.range)
      end

      def summary
        count = scope.count
        total = scope.sum(:amount)
        {
          count: count,
          total: Sql.money(total),
          average_ticket: count.zero? ? 0.0 : Sql.money(total / count),
          missing_amount_count: scope.where(missing_amount: true).count,
          cancelled_count: Sale.cancelled.between(@period.range).count,
          by_day: by_day,
          top_sellers: top_by(:seller_id, User, :name),
          top_products: top_by(:product_id, Product, :name)
        }
      end

      def by_day
        rows = scope.group(Sql.local_date('sales.sold_at')).pluck(Sql.local_date('sales.sold_at'), Arel.sql('COUNT(*)'),
                                                                  Arel.sql('SUM(sales.amount)'))
        indexed = rows.to_h { |date, count, amount| [date.to_date, [count, amount]] }
        @period.dates.map do |date|
          count, amount = indexed[date] || [0, 0]
          { date: date.iso8601, count: count, total: Sql.money(amount) }
        end
      end

      private

      def top_by(column, model, label)
        rows = scope.where.not(column => nil).group(column)
                    .order(Arel.sql('SUM(sales.amount) DESC')).limit(TOP)
                    .pluck(column, Arel.sql('COUNT(*)'), Arel.sql('SUM(sales.amount)'))
        names = model.where(id: rows.map(&:first)).pluck(:id, label).to_h
        rows.map { |id, count, amount| { id: id, name: names[id], count: count, total: Sql.money(amount) } }
      end
    end
  end
end
