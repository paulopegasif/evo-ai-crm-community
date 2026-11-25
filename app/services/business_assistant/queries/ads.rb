# frozen_string_literal: true

# Gasto e resultados de anúncios da Meta. As tabelas meta_* só existem nas instalações com a
# integração (branches de cliente); sem elas, responde ads_data_available: false em vez de zeros.
module BusinessAssistant
  module Queries
    class Ads
      def initialize(period)
        @period = period
      end

      def available?
        Sql.ads_data_available?
      end

      def spend
        return { ads_data_available: false } unless available?

        totals = select_one(<<~SQL.squish)
          SELECT COALESCE(SUM(spend), 0) AS spend, COALESCE(SUM(impressions), 0) AS impressions,
                 COALESCE(SUM(clicks), 0) AS clicks, COALESCE(SUM(conversations), 0) AS conversations,
                 COALESCE(SUM(meta_leads), 0) AS meta_leads, MAX(currency) AS currency
          FROM meta_ad_insights_daily WHERE date BETWEEN #{quoted_from} AND #{quoted_to}
        SQL
        {
          ads_data_available: true,
          currency: totals['currency'],
          spend: Sql.money(totals['spend']),
          impressions: totals['impressions'].to_i,
          clicks: totals['clicks'].to_i,
          conversations_started: totals['conversations'].to_i,
          meta_leads: totals['meta_leads'].to_i,
          by_day: by_day,
          by_campaign: by_campaign
        }
      end

      # Gasto e métricas por campanha no período: { meta_campaign_id => {...} }.
      def campaign_rows
        return [] unless available?

        campaigns_join = Sql.table_exists?('meta_campaigns') ? 'LEFT JOIN meta_campaigns c ON c.meta_id = i.meta_campaign_id' : ''
        name = campaigns_join.empty? ? 'NULL' : 'c.name'
        select_all(<<~SQL.squish)
          SELECT i.meta_campaign_id AS campaign_id, MAX(#{name}) AS name, SUM(i.spend) AS spend,
                 SUM(i.impressions) AS impressions, SUM(i.clicks) AS clicks, SUM(i.conversations) AS conversations,
                 SUM(i.meta_leads) AS meta_leads
          FROM meta_ad_insights_daily i #{campaigns_join}
          WHERE i.date BETWEEN #{quoted_from} AND #{quoted_to}
          GROUP BY i.meta_campaign_id ORDER BY SUM(i.spend) DESC
        SQL
      end

      # Mapa ad_id (Meta) → campaign_id, para ligar leads (contacts.additional_attributes.ad_id) às campanhas.
      def ad_campaign_map
        return {} unless Sql.table_exists?('meta_ads')

        select_all('SELECT meta_id, meta_campaign_id FROM meta_ads').to_h { |row| [row['meta_id'], row['meta_campaign_id']] }
      end

      private

      def by_day
        rows = select_all(<<~SQL.squish).to_h { |row| [row['date'].to_date, row['spend']] }
          SELECT date, SUM(spend) AS spend FROM meta_ad_insights_daily
          WHERE date BETWEEN #{quoted_from} AND #{quoted_to} GROUP BY date
        SQL
        @period.dates.map { |date| { date: date.iso8601, spend: Sql.money(rows[date] || 0) } }
      end

      def by_campaign
        campaign_rows.map do |row|
          { campaign_id: row['campaign_id'], name: row['name'], spend: Sql.money(row['spend']),
            impressions: row['impressions'].to_i, clicks: row['clicks'].to_i,
            conversations_started: row['conversations'].to_i, meta_leads: row['meta_leads'].to_i }
        end
      end

      def quoted_from
        connection.quote(@period.from)
      end

      def quoted_to
        connection.quote(@period.to)
      end

      def select_one(sql)
        connection.select_one(sql)
      end

      def select_all(sql)
        connection.select_all(sql).to_a
      end

      def connection
        ActiveRecord::Base.connection
      end
    end
  end
end
