# frozen_string_literal: true

# Desempenho por campanha da Meta: gasto (insights) cruzado com leads e vendas do CRM, ligados pela
# origem gravada no contato (ad_id → campanha, ou utm_campaign = nome da campanha).
module BusinessAssistant
  module Analytics
    class Campaigns
      def initialize(period)
        @period = period
        @ads = Queries::Ads.new(period)
      end

      def call
        return { ads_data_available: false, campaigns: [] } unless @ads.available?

        rows = @ads.campaign_rows
        resolver = campaign_resolver(rows)
        leads = tally(lead_origins, resolver) { 1 }
        sales = tally(sale_origins, resolver) { |row| row[:amount] }
        sale_counts = tally(sale_origins, resolver) { 1 }

        {
          ads_data_available: true,
          campaigns: rows.map { |row| campaign_metrics(row, leads, sales, sale_counts) },
          unattributed: { crm_leads: leads[nil].to_i, sales_count: sale_counts[nil].to_i, revenue: Sql.money(sales[nil] || 0) }
        }
      end

      private

      def campaign_metrics(row, leads, sales, sale_counts)
        id = row['campaign_id']
        spend = row['spend'].to_d
        crm = { crm_leads: leads[id].to_i, sales_count: sale_counts[id].to_i, revenue: (sales[id] || 0).to_d }
        insight_metrics(row).merge(crm).merge(revenue: Sql.money(crm[:revenue])).merge(efficiency(spend, crm))
      end

      def insight_metrics(row)
        { campaign_id: row['campaign_id'], name: row['name'], spend: Sql.money(row['spend']),
          impressions: row['impressions'].to_i, clicks: row['clicks'].to_i,
          meta_leads: row['meta_leads'].to_i, conversations_started: row['conversations'].to_i }
      end

      def efficiency(spend, crm)
        {
          cost_per_lead: crm[:crm_leads].zero? ? nil : Sql.money(spend / crm[:crm_leads]),
          cost_per_sale: crm[:sales_count].zero? ? nil : Sql.money(spend / crm[:sales_count]),
          roas: spend.zero? ? nil : (crm[:revenue] / spend).round(2).to_f,
          lead_to_sale_pct: Sql.pct(crm[:sales_count], crm[:crm_leads])
        }
      end

      # Origem → campaign_id (nil quando não dá para ligar a nenhuma campanha com gasto).
      def campaign_resolver(rows)
        by_ad = @ads.ad_campaign_map
        by_name = rows.each_with_object({}) { |row, map| map[row['name'].to_s.downcase] = row['campaign_id'] if row['name'] }
        lambda do |origin|
          by_ad[origin[:ad_id]] || by_name[origin[:utm_campaign].to_s.downcase]
        end
      end

      def tally(origins, resolver)
        origins.each_with_object(Hash.new(0)) { |origin, acc| acc[resolver.call(origin)] += yield(origin) }
      end

      def lead_origins
        Queries::Leads.new_leads(@period)
                      .pluck(Arel.sql("contacts.additional_attributes ->> 'ad_id'"),
                             Arel.sql("contacts.additional_attributes ->> 'utm_campaign'"))
                      .map { |ad_id, utm| { ad_id: ad_id.presence, utm_campaign: utm.presence } }
      end

      def sale_origins
        @sale_origins ||= Sale.active.between(@period.range).left_joins(:contact)
                              .pluck(Arel.sql("contacts.additional_attributes ->> 'ad_id'"),
                                     Arel.sql("contacts.additional_attributes ->> 'utm_campaign'"), :amount)
                              .map { |ad_id, utm, amount| { ad_id: ad_id.presence, utm_campaign: utm.presence, amount: amount.to_d } }
      end
    end
  end
end
