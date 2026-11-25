# frozen_string_literal: true

# Simulação linear de investimento: mantém custo por lead, conversão e ticket observados no período.
# É sempre uma estimativa; o agente recomenda, nunca altera a campanha.
module BusinessAssistant
  module Analytics
    class BudgetSimulation
      MIN_LEADS_FOR_CONFIDENCE = 20

      class Invalid < StandardError; end

      def initialize(period, budget:, campaign_id: nil)
        @period = period
        @budget = parse_budget(budget)
        @campaign_id = campaign_id.presence
      end

      def call
        campaigns = Campaigns.new(@period).call
        return { ads_data_available: false, estimate: true } unless campaigns[:ads_data_available]

        base = baseline(campaigns[:campaigns])
        result = { estimate: true, budget: Sql.money(@budget), campaign_id: @campaign_id, baseline: base }
        return result.merge(insufficient_data: true, reason: 'sem leads ou gasto no período para estimar') if base[:cost_per_lead].nil?

        result.merge(projection(base)).merge(
          low_confidence: base[:crm_leads] < MIN_LEADS_FOR_CONFIDENCE,
          assumptions: ['custo por lead constante', 'mesma taxa de conversão de lead em venda', 'mesmo ticket médio',
                        'resposta linear ao investimento (na prática há saturação)']
        )
      end

      private

      def parse_budget(value)
        amount = BigDecimal(value.to_s)
        raise Invalid, 'budget deve ser maior que zero' unless amount.positive?

        amount
      rescue ArgumentError, TypeError
        raise Invalid, 'budget deve ser um número (ex.: 3000)'
      end

      def baseline(rows)
        rows = rows.select { |row| row[:campaign_id] == @campaign_id } if @campaign_id
        raise Invalid, 'campanha sem dados no período' if @campaign_id && rows.empty?

        totals = %i[spend crm_leads sales_count revenue].index_with { |key| rows.sum { |r| r[key] }.to_d }
        { spend: Sql.money(totals[:spend]), crm_leads: totals[:crm_leads].to_i, sales_count: totals[:sales_count].to_i,
          revenue: Sql.money(totals[:revenue]) }.merge(rates(totals))
      end

      def rates(totals)
        {
          cost_per_lead: ratio(totals[:spend], totals[:crm_leads]) { |v| Sql.money(v) },
          lead_to_sale_rate: ratio(totals[:sales_count], totals[:crm_leads]) { |v| v.round(4).to_f } || 0.0,
          average_ticket: ratio(totals[:revenue], totals[:sales_count]) { |v| Sql.money(v) } || 0.0
        }
      end

      def ratio(numerator, denominator)
        return nil if numerator.zero? || denominator.zero?

        yield(numerator / denominator)
      end

      def projection(base)
        leads = @budget / base[:cost_per_lead].to_d
        sales = leads * base[:lead_to_sale_rate].to_d
        revenue = sales * base[:average_ticket].to_d
        {
          estimated_leads: leads.round(1).to_f, estimated_sales: sales.round(1).to_f,
          estimated_revenue: Sql.money(revenue),
          estimated_roas: (revenue / @budget).round(2).to_f
        }
      end
    end
  end
end
