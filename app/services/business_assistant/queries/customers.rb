# frozen_string_literal: true

# Busca, histórico e rankings de clientes (contatos com vendas), sem contatos internos.
module BusinessAssistant
  module Queries
    class Customers
      SEARCH_LIMIT = 10
      HISTORY_LIMIT = 20
      MAX_RANKING = 50
      RANKINGS = %w[recent top_spenders most_frequent inactive].freeze

      class InvalidRanking < StandardError; end

      def search(query)
        term = query.to_s.strip
        return [] if term.length < 2

        like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        digits = term.gsub(/\D/, '')
        scope = contacts.where('contacts.name ILIKE :q OR contacts.email ILIKE :q', q: like)
        scope = scope.or(contacts.where('contacts.phone_number LIKE ?', "%#{digits}%")) if digits.length >= 6
        found = scope.limit(SEARCH_LIMIT).to_a
        stats = sale_stats(found.map(&:id))
        found.map { |contact| contact_summary(contact, stats[contact.id]) }
      end

      def history(contact_id)
        contact = contacts.find(contact_id)
        sales = Sale.active.where(contact_id: contact.id).includes(:product, :seller).order(sold_at: :desc)
        {
          customer: contact_summary(contact, sale_stats([contact.id])[contact.id]),
          sales: sales.limit(HISTORY_LIMIT).map { |sale| sale_row(sale) },
          products: products_bought(contact.id),
          open_deals: open_deals(contact.id),
          origin: contact.additional_attributes.to_h.slice('utm_source', 'utm_campaign', 'ad_id', 'attribution_channel')
        }
      end

      def ranking(kind, limit: 10, period: nil)
        raise InvalidRanking, "ranking inválido (use: #{RANKINGS.join(', ')})" unless RANKINGS.include?(kind.to_s)

        limit = limit.to_i.clamp(1, MAX_RANKING)
        rows = ranking_rows(kind.to_s, limit, period)
        contacts_by_id = contacts.where(id: rows.map(&:first)).index_by(&:id)
        rows.filter_map do |id, count, total, last_at|
          contact = contacts_by_id[id]
          next unless contact

          { id: id, name: contact.name, phone: contact.phone_number, purchases: count, total: Sql.money(total),
            last_purchase_at: last_at&.iso8601, days_since_last_purchase: days_since(last_at) }
        end
      end

      private

      def contacts
        Contact.where.not(id: DailySummary::Exclusion.internal_contact_ids)
      end

      def ranking_rows(kind, limit, period)
        scope = Sale.active.where.not(contact_id: nil)
        scope = scope.between(period.range) if period && kind != 'inactive'
        grouped = scope.group(:contact_id)
        grouped = case kind
                  when 'recent' then grouped.order(Arel.sql('MAX(sales.sold_at) DESC'))
                  when 'top_spenders' then grouped.order(Arel.sql('SUM(sales.amount) DESC'))
                  when 'most_frequent' then grouped.order(Arel.sql('COUNT(*) DESC, SUM(sales.amount) DESC'))
                  else # inactive: compravam e sumiram (sem compra há 45+ dias), quem mais gastou primeiro
                    grouped.having('MAX(sales.sold_at) < ?', 45.days.ago).order(Arel.sql('SUM(sales.amount) DESC'))
                  end
        grouped.limit(limit).pluck(:contact_id, Arel.sql('COUNT(*)'), Arel.sql('SUM(sales.amount)'),
                                   Arel.sql('MAX(sales.sold_at)'))
      end

      def sale_stats(contact_ids)
        Sale.active.where(contact_id: contact_ids).group(:contact_id)
            .pluck(:contact_id, Arel.sql('COUNT(*)'), Arel.sql('SUM(sales.amount)'), Arel.sql('MIN(sales.sold_at)'),
                   Arel.sql('MAX(sales.sold_at)'))
            .to_h { |id, count, total, first, last| [id, { count: count, total: total, first: first, last: last }] }
      end

      def contact_summary(contact, stats)
        stats ||= { count: 0, total: 0 }
        {
          id: contact.id, name: contact.name, phone: contact.phone_number, email: contact.email,
          customer_since: contact.created_at.to_date.iso8601,
          purchases: stats[:count], total_spent: Sql.money(stats[:total]),
          first_purchase_at: stats[:first]&.iso8601, last_purchase_at: stats[:last]&.iso8601,
          days_since_last_purchase: days_since(stats[:last])
        }
      end

      def sale_row(sale)
        { id: sale.id, sold_at: sale.sold_at.iso8601, amount: Sql.money(sale.amount), product: sale.product&.name,
          product_kind: sale.product&.kind, seller: sale.seller&.name, notes: sale.notes.to_s.first(200).presence }
      end

      def products_bought(contact_id)
        Sale.active.where(contact_id: contact_id).where.not(product_id: nil).joins(:product)
            .group('products.name', 'products.kind').order(Arel.sql('COUNT(*) DESC'))
            .pluck('products.name', 'products.kind', Arel.sql('COUNT(*)'), Arel.sql('SUM(sales.amount)'))
            .map { |name, kind, count, total| { name: name, kind: kind, purchases: count, total: Sql.money(total) } }
      end

      def open_deals(contact_id)
        PipelineItem.joins(:pipeline, :pipeline_stage).left_joins(:conversation)
                    .where('pipeline_items.contact_id = :id OR conversations.contact_id = :id', id: contact_id)
                    .where(completed_at: nil)
                    .where(pipeline_stages: { stage_type: PipelineStage.stage_types[:active] })
                    .pluck('pipelines.name', 'pipeline_stages.name')
                    .map { |pipeline, stage| { pipeline: pipeline, stage: stage } }
      end

      def days_since(time)
        return nil unless time

        (Sales::TimeZone.today - time.in_time_zone(Sales::TimeZone.current).to_date).to_i
      end
    end
  end
end
