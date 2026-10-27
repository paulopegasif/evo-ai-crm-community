# frozen_string_literal: true

module Dashboard
  class LeadTrackingService
    def initialize(params:)
      @params = params
      @filters = Dashboard::FiltersBuilder.new(params: params)
    end

    def call
      time_range = @filters.time_range

      contacts = Contact.where(created_at: time_range)
      appointments = Appointment.where(start_time: time_range)

      if @params[:user_id].present? && @params[:user_id] != '__all__'
        appointments = appointments.where(user_id: @params[:user_id])
      end

      @filters_contacts = contacts
      @filters_appointments = appointments

      # Contact counts
      total_leads = contacts.count
      
      # Appointments breakdown
      total_scheduled = appointments.count
      total_attended = appointments.where(status: 'attended').count
      total_no_show = appointments.where(status: 'no_show').count
      total_confirmed = appointments.where(status: %w[confirmed scheduled]).count
      total_cancelled = appointments.where(status: 'cancelled').count

      # Contacts who scheduled
      scheduled_contact_ids = appointments.where.not(contact_id: nil).pluck(:contact_id).uniq
      attended_contact_ids = appointments.where(status: 'attended').where.not(contact_id: nil).pluck(:contact_id).uniq

      # Qualified leads (has appointment OR moved in pipeline)
      pipeline_contact_ids = PipelineItem.where(created_at: time_range).where.not(contact_id: nil).pluck(:contact_id).uniq
      qualified_contact_ids = (scheduled_contact_ids + pipeline_contact_ids).uniq
      total_qualified = qualified_contact_ids.count

      # Won leads
      won_pipeline_items = PipelineItem.joins(:pipeline_stage)
                                       .where(pipeline_stages: { stage_type: PipelineStage.stage_types[:completed] })
                                       .where(created_at: time_range)
      won_contact_ids = (attended_contact_ids + won_pipeline_items.pluck(:contact_id)).compact.uniq
      total_won = won_contact_ids.count

      # Financial calculations
      appointment_revenue = appointments.where(status: 'attended').sum(:price).to_f
      total_revenue = appointment_revenue
      avg_ticket = total_won.positive? ? (total_revenue / total_won).round(2) : 0.0

      # Conversion Rates
      qualification_rate = total_leads.positive? ? ((total_qualified.to_f / total_leads) * 100).round(1) : 0.0
      scheduling_rate = total_leads.positive? ? ((scheduled_contact_ids.count.to_f / total_leads) * 100).round(1) : 0.0
      total_shows_and_no_shows = total_attended + total_no_show
      show_rate = total_shows_and_no_shows.positive? ? ((total_attended.to_f / total_shows_and_no_shows) * 100).round(1) : (total_scheduled.positive? ? 100.0 : 0.0)
      conversion_rate = total_leads.positive? ? ((total_won.to_f / total_leads) * 100).round(1) : 0.0

      {
        period: {
          since: time_range.begin.to_i,
          until: time_range.end.to_i,
          days: ((time_range.end.to_date - time_range.begin.to_date).to_i + 1)
        },
        kpis: {
          total_leads: total_leads,
          total_qualified: total_qualified,
          total_scheduled: total_scheduled,
          total_attended: total_attended,
          total_no_show: total_no_show,
          total_confirmed: total_confirmed,
          total_cancelled: total_cancelled,
          total_won: total_won,
          qualification_rate: qualification_rate,
          scheduling_rate: scheduling_rate,
          show_rate: show_rate,
          conversion_rate: conversion_rate,
          total_revenue: total_revenue,
          average_ticket: avg_ticket,
          **build_ad_kpis(contacts)
        },
        funnel: [
          { stage: 'Total de Leads', count: total_leads, percentage: 100.0, color: '#C084FC' },
          { stage: 'Qualificados', count: total_qualified, percentage: qualification_rate, color: '#A855F7' },
          { stage: 'Agendados', count: scheduled_contact_ids.count, percentage: scheduling_rate, color: '#967AB4' },
          { stage: 'Compareceram', count: total_attended, percentage: total_leads.positive? ? ((total_attended.to_f / total_leads) * 100).round(1) : 0.0, color: '#3B82F6' },
          { stage: 'Convertidos / Venda', count: total_won, percentage: conversion_rate, color: '#10B981' }
        ],
        sources: build_sources(contacts, appointments),
        campaigns: build_campaigns(contacts, appointments),
        professionals: build_professionals(appointments),
        categories: build_categories(appointments),
        timeline: build_timeline(time_range, contacts, appointments)
      }
    end

    private

    def build_sources(contacts, appointments)
      sources_hash = Hash.new { |h, k| h[k] = { name: k, leads: 0, scheduled: 0, attended: 0, won: 0, revenue: 0.0 } }

      contacts.pluck(:id).each { |id| sources_hash[attribution_for(id)[:source]][:leads] += 1 }

      appointment_rows(appointments).each do |contact_id, status, price|
        row = sources_hash[attribution_for(contact_id)[:source]]
        row[:scheduled] += 1
        next unless status == 'attended'

        row[:attended] += 1
        row[:won] += 1
        row[:revenue] += price.to_f
      end

      sources_hash.values.map do |s|
        rate = s[:leads].positive? ? ((s[:won].to_f / s[:leads]) * 100).round(1) : 0.0
        s.merge(conversion_rate: rate)
      end.sort_by { |s| -s[:leads] }
    end

    def build_campaigns(contacts, appointments)
      campaigns_hash = {}
      row_for = lambda do |attribution|
        campaigns_hash[attribution[:campaign_key]] ||= {
          campaign_key: attribution[:campaign_key],
          meta_campaign_id: attribution[:meta_campaign_id],
          name: attribution[:campaign_name],
          source: attribution[:source],
          leads: 0, scheduled: 0, attended: 0, won_contact_ids: Set.new, revenue: 0.0
        }
      end

      contacts.pluck(:id).each { |id| row_for.call(attribution_for(id))[:leads] += 1 }

      appointment_rows(appointments).each do |contact_id, status, price|
        row = row_for.call(attribution_for(contact_id))
        row[:scheduled] += 1
        next unless status == 'attended'

        row[:attended] += 1
        row[:won_contact_ids] << contact_id
        row[:revenue] += price.to_f
      end

      # Campaigns that spent in the period without any attributed lead still show up.
      (campaign_spend.keys - campaigns_hash.values.filter_map { |c| c[:meta_campaign_id] }).each do |meta_id|
        row_for.call(meta_campaign_attribution(meta_id, meta_campaign_names[meta_id]))
      end

      campaigns_hash.values.map do |c|
        won = c.delete(:won_contact_ids).size
        spend = c[:meta_campaign_id] ? campaign_spend[c[:meta_campaign_id]] : nil
        c.merge(
          won: won,
          conversion_rate: c[:leads].positive? ? ((won.to_f / c[:leads]) * 100).round(1) : 0.0,
          spend: spend&.to_f,
          cpl: ratio(spend, c[:leads]),
          cac: ratio(spend, won),
          roas: ratio(c[:revenue], spend, precision: 2)
        )
      end.sort_by { |c| [-c[:revenue], -(c[:spend] || 0), -c[:leads]] }
    end

    # Spend KPIs are only meaningful when Meta Ads is (or was) connected.
    def build_ad_kpis(contacts)
      ad_spend = campaign_spend.values.sum.to_f
      has_ad_spend = MetaAds::Integration.current.present? || ad_spend.positive?
      ad_leads = contacts.pluck(:id).count { |id| attribution_for(id)[:from_ad] }

      { ad_spend: ad_spend, ad_leads: ad_leads, avg_cpl: ratio(ad_spend, ad_leads), has_ad_spend: has_ad_spend }
    end

    def appointment_rows(appointments)
      @appointment_rows ||= appointments.where.not(contact_id: nil).pluck(:contact_id, :status, :price)
    end

    # --- Lead attribution (first touch; see Attribution::RecordService) -----------

    SOURCE_SQL = "COALESCE(NULLIF(contacts.additional_attributes->>'utm_source', ''), " \
                 "NULLIF(contacts.custom_attributes->>'utm_source', ''), " \
                 "NULLIF(contacts.custom_attributes->>'channel', ''))"
    UTM_CAMPAIGN_SQL = "COALESCE(NULLIF(contacts.additional_attributes->>'utm_campaign', ''), " \
                       "NULLIF(contacts.custom_attributes->>'utm_campaign', ''))"
    AD_ID_SQL = "NULLIF(contacts.additional_attributes->>'ad_id', '')"
    SOURCE_LABELS = { 'meta_ads' => 'Meta Ads' }.freeze
    UNKNOWN_SOURCE = 'Não informada'
    NO_CAMPAIGN = 'Sem campanha'

    def attribution_for(contact_id)
      attribution_map[contact_id] || no_attribution
    end

    # contact_id => { source:, campaign_key:, campaign_name:, meta_campaign_id:, from_ad: }
    # for every contact counted as a lead or holding an appointment in the period.
    def attribution_map
      @attribution_map ||= begin
        ids = (@filters_contacts.pluck(:id) + appointment_rows(@filters_appointments).map(&:first)).uniq
        Contact.where(id: ids)
               .joins('LEFT JOIN meta_ads ON meta_ads.meta_id = contacts.additional_attributes->>\'ad_id\'')
               .joins('LEFT JOIN meta_campaigns ON meta_campaigns.meta_id = meta_ads.meta_campaign_id')
               .pluck(Arel.sql('contacts.id'), Arel.sql(SOURCE_SQL), Arel.sql(AD_ID_SQL), Arel.sql(UTM_CAMPAIGN_SQL),
                      Arel.sql('meta_campaigns.meta_id'), Arel.sql('meta_campaigns.name'))
               .to_h { |id, source, ad_id, utm_campaign, meta_id, meta_name| [id, build_attribution(source, ad_id, utm_campaign, meta_id, meta_name)] }
      end
    end

    def build_attribution(source, ad_id, utm_campaign, meta_campaign_id, meta_campaign_name)
      return meta_campaign_attribution(meta_campaign_id, meta_campaign_name) if meta_campaign_id.present?

      source_label = SOURCE_LABELS.fetch(source, source.presence || UNKNOWN_SOURCE)
      key, name = if ad_id.present?
                    ["ad:#{ad_id}", "Anúncio #{ad_id}"]
                  elsif utm_campaign.present?
                    ["utm:#{utm_campaign}", utm_campaign]
                  else
                    ['none', NO_CAMPAIGN]
                  end
      { source: source_label, campaign_key: key, campaign_name: name, meta_campaign_id: nil,
        from_ad: ad_id.present? || source == 'meta_ads' }
    end

    def meta_campaign_attribution(meta_id, name)
      { source: SOURCE_LABELS['meta_ads'], campaign_key: "meta:#{meta_id}", campaign_name: name.presence || "Campanha #{meta_id}",
        meta_campaign_id: meta_id, from_ad: true }
    end

    def no_attribution
      { source: UNKNOWN_SOURCE, campaign_key: 'none', campaign_name: NO_CAMPAIGN, meta_campaign_id: nil, from_ad: false }
    end

    # meta_campaign_id => spend (BigDecimal) within the period's calendar days.
    def campaign_spend
      @campaign_spend ||= MetaAds::InsightDaily
                          .where(date: @filters.time_range.begin.to_date..@filters.time_range.end.to_date)
                          .where.not(meta_campaign_id: nil)
                          .group(:meta_campaign_id)
                          .sum(:spend)
    end

    def meta_campaign_names
      @meta_campaign_names ||= MetaAds::Campaign.where(meta_id: campaign_spend.keys).pluck(:meta_id, :name).to_h
    end

    # nil (rendered as "—") when there is no denominator or no numerator source.
    def ratio(numerator, denominator, precision: 2)
      return nil if numerator.nil? || denominator.nil? || denominator.to_f.zero?

      (numerator.to_f / denominator.to_f).round(precision)
    end

    def build_professionals(appointments)
      users = User.where(id: appointments.pluck(:user_id).uniq)
      user_map = users.index_by(&:id)

      prof_hash = Hash.new { |h, k| h[k] = { user_id: k, name: user_map[k]&.name || 'Profissional', total: 0, attended: 0, no_show: 0, revenue: 0.0 } }

      appointments.each do |apt|
        prof_hash[apt.user_id][:total] += 1
        case apt.status
        when 'attended'
          prof_hash[apt.user_id][:attended] += 1
          prof_hash[apt.user_id][:revenue] += apt.price.to_f
        when 'no_show'
          prof_hash[apt.user_id][:no_show] += 1
        end
      end

      prof_hash.values.map do |p|
        denom = p[:attended] + p[:no_show]
        rate = denom.positive? ? ((p[:attended].to_f / denom) * 100).round(1) : (p[:total].positive? ? 100.0 : 0.0)
        p.merge(show_rate: rate)
      end.sort_by { |p| -p[:revenue] }
    end

    def build_categories(appointments)
      cat_hash = Hash.new { |h, k| h[k] = { name: k, count: 0, revenue: 0.0, color: '#967AB4' } }

      # Preset colors from Appointment::CATEGORIES
      color_map = Appointment::CATEGORIES.each_with_object({}) { |c, acc| acc[c[:name]] = c[:color] }

      appointments.each do |apt|
        cat = apt.category || 'Geral'
        cat_hash[cat][:name] = cat
        cat_hash[cat][:count] += 1
        cat_hash[cat][:revenue] += apt.price.to_f if apt.status == 'attended'
        cat_hash[cat][:color] = color_map[cat] || '#967AB4'
      end

      total_count = appointments.count
      cat_hash.values.map do |c|
        share = total_count.positive? ? ((c[:count].to_f / total_count) * 100).round(1) : 0.0
        c.merge(share_percentage: share)
      end.sort_by { |c| -c[:count] }
    end

    def build_timeline(time_range, contacts, appointments)
      days = (time_range.begin.to_date..time_range.end.to_date).to_a
      
      # Limit to last 30 days if range is very long for chart readability
      days = days.last(30) if days.size > 30

      days.map do |d|
        start_d = d.beginning_of_day
        end_d = d.end_of_day

        day_leads = contacts.where('created_at >= ? AND created_at <= ?', start_d, end_d).count
        day_apts = appointments.where('start_time >= ? AND start_time <= ?', start_d, end_d)
        day_attended = day_apts.where(status: 'attended').count
        day_revenue = day_apts.where(status: 'attended').sum(:price).to_f

        {
          date: d.strftime('%Y-%m-%d'),
          label: d.strftime('%d/%m'),
          leads: day_leads,
          scheduled: day_apts.count,
          attended: day_attended,
          revenue: day_revenue
        }
      end
    end
  end
end
