# frozen_string_literal: true

# Progresso de uma meta mensal a partir das vendas ativas do mês (fuso da instalação).
# Ritmo = quanto falta ÷ dias corridos restantes contando hoje (0 quando batida).
module SalesGoals
  class ProgressService
    def initialize(month:, goal: nil, seller: nil, today: Sales::TimeZone.today)
      @month = month.to_date.beginning_of_month
      @goal = goal
      @seller = seller
      @today = today
    end

    def call
      sold = sales_scope.sum(:amount).to_d
      count = sales_scope.count
      goal_amount = @goal&.amount&.to_d
      remaining = goal_amount && [goal_amount - sold, 0].max
      reached = goal_amount.present? && sold >= goal_amount

      {
        goal_id: @goal&.id,
        goal: goal_amount&.to_f,
        sold: sold.to_f,
        count: count,
        percent: goal_amount&.positive? ? ((sold / goal_amount) * 100).round(1).to_f : nil,
        remaining: remaining&.to_f,
        surplus: reached ? (sold - goal_amount).to_f : nil,
        daily_pace: goal_amount && pace(remaining),
        goal_reached: reached,
        days_left: days_left
      }
    end

    private

    def sales_scope
      scope = Sale.active.in_month(@month)
      @seller ? scope.for_seller(@seller) : scope
    end

    # Dias restantes no mês contando hoje; mês passado = 0; mês futuro = mês inteiro.
    def days_left
      month_end = @month.end_of_month
      return 0 if @today > month_end
      return (month_end - @month).to_i + 1 if @today < @month

      (month_end - @today).to_i + 1
    end

    def pace(remaining)
      return 0.0 if remaining.zero?
      return nil if days_left.zero?

      (remaining / days_left).round(2).to_f
    end
  end
end
